# 8byte Banking Platform — DevOps Infrastructure

End-to-end DevOps implementation for the 8byte banking and financial services platform. Built on AWS using Terraform, Jenkins, Kubernetes (EKS), Prometheus, and Grafana.

---

## Architecture overview

```
                        ┌─────────────────────────────────────┐
                        │           AWS VPC (10.0.0.0/16)      │
                        │                                       │
  Internet ────────────►│  Public Subnets (10.0.1-3.0/24)      │
                        │  ├── Jenkins EC2 (t3.large)           │
                        │  └── SonarQube EC2 (t3.medium)        │
                        │                                       │
                        │  Private Subnets (10.0.11-13.0/24)   │
                        │  ├── EKS Worker Nodes                 │
                        │  │   ├── namespace: staging           │
                        │  │   ├── namespace: production        │
                        │  │   └── namespace: monitoring        │
                        │  └── RDS PostgreSQL                   │
                        └─────────────────────────────────────┘
```

### Tech stack

| Layer | Tool | Purpose |
|---|---|---|
| Infrastructure | Terraform | Infrastructure as code |
| Cloud | AWS ap-south-1 | Mumbai region |
| Container orchestration | Amazon EKS v1.31 | Managed Kubernetes |
| CI/CD | Jenkins | Self-hosted pipeline |
| Code quality | SonarQube | Static analysis |
| Security scanning | Trivy | Vulnerability scanning |
| Image registry | Amazon ECR | Private Docker registry |
| Database | RDS PostgreSQL 15.10 | Managed database |
| Monitoring | Prometheus + Grafana | Metrics and dashboards |
| Secret management | AWS Secrets Manager | Database credentials |

---

## Repository structure

```
8byte-devops/
├── bootstrap/                  # Creates S3 + DynamoDB for Terraform state
│   ├── main.tf
│   └── outputs.tf
├── terraform/                  # Main infrastructure
│   ├── backend.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── modules/
│       ├── vpc/                # Networking
│       ├── security-groups/    # Firewall rules
│       ├── eks/                # Kubernetes cluster + ECR
│       ├── rds/                # PostgreSQL database
│       └── jenkins-server/     # Jenkins + SonarQube EC2
├── screenshots/                # Evidence of working implementation
│   ├── phase1/
│   ├── phase2/
│   └── phase3/
└── docs/                       # Detailed documentation
    ├── APPROACH.md
    ├── APPROACH-PHASE2.md
    ├── APPROACH-PHASE3.md
    ├── CHALLENGES.md
    ├── CHALLENGES-PHASE2.md
    ├── CHALLENGES-PHASE3.md
    ├── RECOMMENDATIONS.md
    └── TERRAFORM_STANDARDS.md
```

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Terraform | >= 1.6.0 | [terraform.io](https://terraform.io) |
| AWS CLI | v2.x | [aws.amazon.com/cli](https://aws.amazon.com/cli) |
| kubectl | v1.31 | [kubernetes.io](https://kubernetes.io/docs/tasks/tools) |
| Helm | >= 3.x | [helm.sh](https://helm.sh) |

### AWS setup

1. Create IAM user with `AdministratorAccess`
2. Generate CLI access keys
3. Configure AWS CLI:
```bash
aws configure
# Region: ap-south-1
# Output: json
```
4. Verify:
```bash
aws sts get-caller-identity
```

### SSH key pair

Generate a key pair for EC2 access:
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/8byte-jenkins-key -N ""
```

---

## Phase 1 — Infrastructure setup

### Step 1: Bootstrap remote state

```bash
cd bootstrap
terraform init
terraform apply
```

This creates:
- S3 bucket `8byte-terraform-state-prod` for state storage
- DynamoDB table `8byte-terraform-lock` for state locking

### Step 2: Configure variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
environment             = "prod"
project_name            = "8byte"
my_ip                   = "YOUR_PUBLIC_IP"
jenkins_instance_type   = "t3.large"
sonarqube_instance_type = "t3.medium"
key_name                = "8byte-jenkins-key"
public_key_path         = "~/.ssh/8byte-jenkins-key.pub"
```

### Step 3: Deploy infrastructure

```bash
terraform init
terraform plan
terraform apply
```

Expected duration: 20-25 minutes

### Step 4: Connect kubectl to EKS

```bash
aws eks update-kubeconfig --region ap-south-1 --name 8byte-prod-eks-cluster
kubectl get nodes
```

### Outputs after apply

```
jenkins_public_ip    = "EC2 public IP"
sonarqube_public_ip  = "EC2 public IP"
eks_cluster_name     = "8byte-prod-eks-cluster"
ecr_repository_url   = "188019708471.dkr.ecr.ap-south-1.amazonaws.com/8byte-prod-app"
rds_endpoint         = "eightbyte-prod-postgres..."
```

---

## Phase 2 — CI/CD pipeline setup

### Jenkins configuration

1. Access Jenkins: `http://<jenkins_public_ip>:8080`
2. Install plugins: SonarQube Scanner, Docker Pipeline, Kubernetes CLI, Maven Integration, Pipeline Stage View
3. Configure tools: JDK 21, Maven 3.9.9, SonarQube Scanner
4. Add credentials: GitHub PAT, SonarQube token, AWS keys

### SonarQube configuration

1. Access SonarQube: `http://<sonarqube_public_ip>:9000`
2. Generate token: Administration → Security → Users → Tokens
3. Configure webhook: Administration → Webhooks → `http://<jenkins_private_ip>:8080/sonarqube-webhook/`

### Pipeline

The Jenkins multibranch pipeline reads `Jenkinsfile` from the application repository.

**PR builds** run: checkout → compile → test → trivy fs scan → sonarqube → quality gate

**Main branch builds** run full pipeline:
```
checkout → compile → test → trivy fs scan → sonarqube →
quality gate → build → docker build → trivy image scan →
push to ECR → deploy to staging → manual approval → deploy to production
```

Application repository: [https://github.com/Rahulbs06/8byte-banking-app](https://github.com/Rahulbs06/8byte-banking-app)

---

## Phase 3 — Monitoring setup

Install Prometheus and Grafana on EKS:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=your-password
```

Expose Grafana externally:
```bash
kubectl patch svc kube-prometheus-stack-grafana \
  -n monitoring \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

### Dashboards

| Dashboard | ID | Purpose |
|---|---|---|
| Node Exporter Full | 1860 | CPU, memory, disk per node |
| Kubernetes cluster monitoring | 3119 | Pod, container, namespace metrics |

---

## Architecture decisions

### Single EKS cluster with namespaces

Used one EKS cluster with three namespaces (`staging`, `production`, `monitoring`) instead of separate clusters per environment. Namespaces provide sufficient isolation for this scale while reducing cost and operational overhead.

### Remote state management

Terraform state stored in S3 with DynamoDB locking. A separate `bootstrap` module creates the state infrastructure using local state — keeping everything as code without manual AWS CLI steps.

### Jenkins over GitHub Actions

Jenkins is self-hosted — all pipeline execution and credentials stay within our infrastructure. For a banking platform, build logs and secrets must not leave the organisation's network boundary.

### ECR over Docker Hub

ECR is co-located with EKS in the same AWS region. Image pulls happen over the AWS internal network — faster, no egress charges, and images stay within the AWS account boundary.

---

## Security considerations

### Network security

- RDS is in private subnets only — no path from internet to database
- EKS worker nodes in private subnets — not directly reachable from internet
- ALB security group accepts only ports 80 and 443 from internet
- RDS security group accepts port 5432 from EKS nodes only
- Jenkins SSH access restricted to engineer IP only

### Data security

- RDS storage encrypted at rest
- Secrets Manager stores database credentials — never in code or environment variables
- ECR images scanned for vulnerabilities on push
- Trivy scans both filesystem and Docker image in the pipeline

### Application security

- Docker containers run as non-root user `appuser`
- SonarQube quality gate checks for security vulnerabilities before build
- AWS WAF recommended for production ALB (not implemented in assignment)

### IAM security

- Dedicated `terraform-deployer` IAM user — not root
- Root access keys deactivated
- EKS nodes use IAM roles — no static credentials on nodes

---

## Cost optimization

### Assignment vs production

| Resource | Assignment config | Production config | Saving |
|---|---|---|---|
| NAT Gateway | 1 (single AZ) | 3 (one per AZ) | ~$64/month |
| RDS | Single AZ, db.t3.medium | Multi-AZ, db.r6g.large | ~$175/month |
| EKS nodes | 2x t3.medium | 3x m5.xlarge | varies |

### Current monthly estimate (assignment)

| Resource | Cost |
|---|---|
| EKS cluster | ~$72 |
| EC2 nodes 2x t3.medium | ~$60 |
| Jenkins t3.large | ~$60 |
| SonarQube t3.medium | ~$30 |
| RDS db.t3.medium | ~$50 |
| NAT Gateway | ~$32 |
| **Total** | **~$304/month** |

### Cost saving tips

- Destroy infrastructure when not in use: `terraform destroy`
- Recreate when needed: `terraform apply` — takes 20-25 minutes
- Use spot instances for Jenkins and SonarQube in non-critical environments
- Delete ECR images older than 30 days using lifecycle policies

---

## Destroying infrastructure

```bash
# Delete Kubernetes load balancers first
kubectl delete svc eightbyte-app-service -n staging
kubectl delete svc eightbyte-app-service -n production
kubectl delete svc kube-prometheus-stack-grafana -n monitoring
kubectl delete svc kube-prometheus-stack-prometheus -n monitoring

# Wait 2-3 minutes for AWS to clean up ELBs

# Then destroy all infrastructure
cd terraform
terraform destroy
```

---

## Documentation

| Document | Description |
|---|---|
| `docs/APPROACH.md` | Phase 1 infrastructure decisions |
| `docs/APPROACH-PHASE2.md` | Phase 2 CI/CD decisions |
| `docs/APPROACH-PHASE3.md` | Phase 3 monitoring decisions |
| `docs/CHALLENGES.md` | Phase 1 challenges and resolutions |
| `docs/CHALLENGES-PHASE2.md` | Phase 2 challenges and resolutions |
| `docs/CHALLENGES-PHASE3.md` | Phase 3 challenges and resolutions |
| `docs/RECOMMENDATIONS.md` | Production improvement recommendations |
| `docs/TERRAFORM_STANDARDS.md` | Terraform project standards |