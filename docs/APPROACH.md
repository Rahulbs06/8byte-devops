# Approach and architectural decisions

**Project:** 8byte Banking and Financial Services Platform  
**Region:** ap-south-1 (Mumbai)  
**Author:** DevOps Engineer  

---

## Overview

This document explains every significant decision made during the infrastructure provisioning of the 8byte platform — what was chosen, why it was chosen, what the banking-grade alternative would be, and where we simplified for the assignment.

The goal was to build infrastructure that is secure, reproducible, and maintainable — not just something that works.

---

## Tool selection

### Terraform over CloudFormation or CDK

Terraform was chosen because it is cloud-agnostic, has a large module ecosystem, and uses a declarative language (HCL) that reads naturally as documentation. CloudFormation is AWS-specific and would lock the platform to a single provider. CDK requires programming language knowledge to read the infrastructure definition.

For a banking platform that may need to span multiple cloud providers or regions in the future, Terraform is the safer long-term choice.

### EKS over ECS or plain EC2

EKS was chosen because Kubernetes gives fine-grained control over deployment strategies, resource limits, network policies, and namespace-level isolation. ECS is simpler but offers less control over pod-level security and scheduling. Plain EC2 would require managing everything manually.

For a banking platform, the ability to enforce network policies between services, set resource quotas per namespace, and do rolling deployments with zero downtime makes Kubernetes the right choice.

### Jenkins over GitHub Actions or GitLab CI

Jenkins was chosen because it is self-hosted. In banking, all pipeline execution — test results, build artifacts, deployment logs — must stay within the organisation's infrastructure. GitHub Actions runs on GitHub's servers. For a fintech company handling financial data, a self-hosted CI/CD system gives full control over what runs and where.

### Prometheus and Grafana over CloudWatch

CloudWatch is the default AWS monitoring tool, but it locks you to AWS. Prometheus and Grafana are open standards that work across any cloud or on-premise environment. The metrics format (OpenMetrics) is supported by every major monitoring system. For a banking platform that values vendor independence, this is the correct choice.

---

## IAM setup

### Why not root user

Root user has unrestricted access to everything in the AWS account — it can delete all resources, change billing, and close the account itself. Using root for day-to-day operations violates the principle of least privilege and means a single leaked credential can cause total account compromise.

A dedicated `terraform-deployer` IAM user was created for all infrastructure operations. Root user access keys were deactivated immediately. Root is now used only for console access with MFA enabled.

### Why AdministratorAccess for the assignment

In a production banking environment, the Terraform IAM user would have a custom policy scoped to exactly the services it needs — EC2, EKS, RDS, VPC, S3, DynamoDB, KMS, Secrets Manager, WAF, and ALB — nothing else. This is called least-privilege access.

For this assignment, `AdministratorAccess` was attached to avoid policy gaps during rapid iteration. The understanding is that this would be replaced with a tightly scoped policy before any production use.

---

## State management

### Why remote state

Terraform state tracks which real-world resources correspond to which Terraform resources. Without remote state, this file lives on the local machine. If the machine is lost, crashed, or handed off to another engineer, the ability to manage existing infrastructure is gone — you cannot safely update or destroy resources without the state.

Remote state in S3 solves this by storing state centrally with versioning enabled, so every change is recorded and any version can be restored.

### Why DynamoDB for locking

If two engineers run `terraform apply` at the same time against the same state, both reads of the state happen before either write — resulting in one apply silently overwriting the other's changes. DynamoDB provides a simple lock: the first `apply` writes a lock record, and any subsequent `apply` sees the lock and waits or fails. This prevents state corruption.

### Why a separate bootstrap module

Terraform needs the S3 bucket and DynamoDB table to exist before it can use them as a backend. But those resources are created by Terraform. The typical solution is to create them manually via the AWS CLI. This was avoided because manual steps are not reproducible, not auditable, and easy to get wrong.

Instead, a `bootstrap/` Terraform module was created that uses local state intentionally. It creates only the S3 bucket and DynamoDB table. Once applied, the main infrastructure points to that bucket as its backend. Everything is code from the first resource to the last.

---

## Networking

### VPC design

A dedicated VPC was created with a `/16` CIDR block giving 65,536 addresses — enough headroom for the platform to grow significantly without a re-IP.

Three availability zones were used. AWS recommends at minimum two, and three is the standard for any production workload. Deploying across three AZs means the platform can survive the failure of an entire AZ and still serve traffic.

Public subnets hold only the NAT Gateway and the Application Load Balancer. Private subnets hold EKS worker nodes and RDS. Nothing in the private subnets is directly reachable from the internet.

### NAT Gateway — one vs three

Banking-grade production practice is one NAT Gateway per AZ. If an AZ goes down and it hosts the only NAT Gateway, nodes in other AZs lose all outbound internet connectivity — they cannot pull Docker images, reach external APIs, or communicate with AWS services that are not VPC endpoints.

For this assignment, a single NAT Gateway was used to reduce cost. This decision is documented explicitly and would be reversed before any production deployment.

### VPC endpoints — not implemented for assignment

In production, VPC endpoints would be created for ECR, Secrets Manager, and S3. This keeps all traffic between EKS nodes and AWS services on the AWS private network — it never leaves to the public internet. This reduces attack surface, improves latency, and reduces data transfer costs.

This was not implemented in the assignment to keep the scope manageable. It is a straightforward addition to the VPC module.

---

## Security groups

Security groups were designed using a strict least-privilege model:

The ALB security group accepts only HTTPS (443) and HTTP (80) from the internet. HTTP exists only to redirect to HTTPS — no plaintext traffic reaches the application.

The EKS nodes security group accepts traffic from the ALB security group only, plus node-to-node traffic for pod networking. It does not accept connections from any other source.

The RDS security group accepts port 5432 only from the EKS nodes security group. There is no path from the internet, the ALB, or any other source to the database. This is the most critical security boundary in the system.

---

## EKS cluster

### Kubernetes version 1.31

Started with version 1.29 — the node group creation failed because the required AMI was not available in ap-south-1. Moved to 1.31 which is the current stable version with full AMI availability in the Mumbai region.

### Private API endpoint

The EKS API server endpoint has private access enabled. This means the control plane communicates with worker nodes over the private network. Public access is also enabled because the assignment is run from a local machine outside the VPC — in production this would be disabled and kubectl access would go through a VPN.

### ON_DEMAND node capacity

Worker nodes use ON_DEMAND instances rather than SPOT instances. Spot instances can be interrupted with two minutes notice when AWS needs the capacity back. For a banking application processing financial transactions, unexpected node termination mid-request is not acceptable. ON_DEMAND nodes cost more but provide predictable availability.

### Namespace isolation

Three namespaces are used to isolate workloads within the single EKS cluster:

`staging` receives automatic deployments on every merge to the main branch. It runs at reduced capacity and is used for integration testing and smoke testing before production.

`production` receives deployments only after a human approval step in the Jenkins pipeline. It runs at full capacity and serves real users.

`monitoring` runs Prometheus, Grafana, and Loki. Keeping monitoring in a separate namespace means it has its own resource quotas and is not affected by application deployments.

### Why a single cluster not two

Two separate clusters — one for staging, one for production — would double the EKS control plane cost ($0.10/hour per cluster) and add significant operational overhead. Namespace isolation with RBAC provides sufficient separation for this scale. The decision would be revisited if regulatory requirements demanded full infrastructure separation between environments.

---

## RDS PostgreSQL

### Why PostgreSQL

PostgreSQL is the standard open-source relational database for financial applications. It supports ACID transactions, has mature support for row-level security, and handles complex queries well. It is also fully supported by AWS RDS with managed backups, patching, and monitoring.

### Single AZ for assignment

Production banking databases must use Multi-AZ deployment. Multi-AZ keeps a synchronous standby replica in a different AZ and automatically fails over within 60-120 seconds if the primary instance has a problem. For a system handling financial transactions, this is not optional.

Single AZ was used for the assignment to reduce cost. The RDS instance costs approximately $25/month in this configuration. Multi-AZ would double that to $50/month. The assignment environment does not serve real traffic, so single AZ is acceptable with explicit documentation.

### Secrets Manager for credentials

The database password is generated randomly by Terraform using the `random_password` resource and immediately stored in AWS Secrets Manager. It is never written to a file, never appears in plaintext in Terraform outputs, and never appears in application environment variables directly.

Applications retrieve the secret at runtime by calling Secrets Manager. This means if a credential rotation is needed, only the Secrets Manager value needs to change — no redeployment required.

---

## ALB and ingress

### Why the manual ALB was removed

The first implementation created an ALB manually via Terraform. This was wrong. When using EKS, the AWS Load Balancer Controller is responsible for creating and managing ALBs based on Kubernetes Ingress objects. Creating an ALB manually creates a parallel, unmanaged resource that conflicts with the ingress controller's work — two ALBs would exist with no automatic coordination between them.

The manual ALB module was destroyed and removed. The ALB for the application will be created automatically when the Ingress object is deployed in Phase 2.

### What the ingress controller does

The AWS Load Balancer Controller runs as a pod inside the EKS cluster. It watches the Kubernetes API for Ingress objects. When one is created, it calls the AWS API to provision an ALB, configure target groups, and set up routing rules. When the Ingress object is deleted, it tears down the ALB. This lifecycle management is handled entirely by the controller — no Terraform involvement after the initial setup.

---

## What is different from production banking

| Area | Assignment | Production banking |
|---|---|---|
| NAT Gateway | 1 (cost saving) | 1 per AZ |
| RDS | Single AZ | Multi-AZ with read replica |
| EKS endpoint | Public + private | Private only, VPN for kubectl |
| IAM | AdministratorAccess | Least-privilege custom policy |
| VPC endpoints | Not implemented | ECR, S3, Secrets Manager |
| WAF | Not implemented | Required on ALB |
| KMS | Default encryption | Customer-managed KMS keys |
| Backup | 7-day RDS snapshots | Cross-region backup, point-in-time recovery |

Every item in this table is documented because the assignment asks for justification of approach. The simplifications were made deliberately to keep the assignment cost and scope manageable, not because the production requirements are unknown.
