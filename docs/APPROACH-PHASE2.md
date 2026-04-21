# Approach and architectural decisions

**Project:** 8byte Banking and Financial Services Platform  
**Region:** ap-south-1 (Mumbai)  
**Author:** Rahul B S

# Phase 2 — CI/CD Pipeline

## Tool decisions

### Jenkins over GitHub Actions

Jenkins is self-hosted — all pipeline execution, build logs, and credentials stay within our infrastructure. For a banking platform this is required. GitHub Actions runs on GitHub's servers which means build logs and potentially secrets leave our network boundary.

### Multibranch pipeline over simple pipeline

A multibranch pipeline automatically discovers branches and pull requests from the repository. This enables different pipeline behavior per branch — PR builds run only CI stages, main branch runs full deployment. A simple pipeline job cannot distinguish between branch types.

### SonarQube on separate EC2

SonarQube needs minimum 2GB RAM for its Elasticsearch process. Running it on the same Jenkins EC2 would cause memory contention during Maven builds, Docker builds, and SonarQube analysis happening simultaneously. Separate EC2 gives each tool dedicated resources.

### ECR over Docker Hub

ECR is co-located with EKS in the same AWS region. Image pulls happen over the AWS internal network — faster and no egress charges. Docker Hub is a public registry which adds latency and potential rate limiting. For a banking platform, keeping images in a private registry within the same cloud account is also a security requirement.

### No Nexus artifact repository

The assignment does not require artifact storage. Nexus adds another EC2, another cost, and another tool to maintain. Since we containerise the application directly from the Maven build output, there is no need to store JAR files separately. The Docker image in ECR serves as the deployment artifact.

---

## Pipeline design decisions

### PR build behavior

PR builds run only: checkout → compile → test → trivy filesystem scan → SonarQube analysis → quality gate.

This gives developers fast feedback on code quality and security without triggering deployments. Deployment stages are gated behind `not { changeRequest() }` which correctly identifies PR builds in Jenkins multibranch pipelines.

### Staging before production

Every merge to main deploys to staging automatically. Production deployment requires a human to approve via Jenkins `input()` step. This matches the assignment requirement and reflects real banking deployment practice — no code reaches production without explicit human sign-off.

### Image tagging with build number

Docker images are tagged with `${BUILD_NUMBER}` — the Jenkins build number. This gives every image a unique, traceable identifier. The same image is also tagged `latest` for convenience. In production, using git SHA as the tag would be more precise.

### Private IP for internal communication

Jenkins and SonarQube communicate using private IPs within the VPC. SonarQube webhook calls Jenkins on `10.0.1.216:8080`. Jenkins calls SonarQube on `10.0.1.211:9000`. Using private IPs keeps traffic within the AWS network — faster, no data transfer costs, reduced attack surface.

---

## Security decisions in Phase 2

### Jenkins port 8080 open to internet

Port 8080 is open to `0.0.0.0/0` to allow GitHub webhook delivery. In production this would be restricted to GitHub's published IP ranges. For the assignment, full open is acceptable.

### Non-root Docker container

The application Dockerfile creates a dedicated `appuser` and runs the JAR as that user. Running containers as root is a security risk — a container escape vulnerability would give root access to the host. Non-root containers limit the blast radius of any container-level exploit.

### Trivy scanning at two points

Trivy scans the filesystem before the Docker build (catches dependency vulnerabilities) and scans the Docker image after building (catches OS-level vulnerabilities introduced by the base image). Two scans at different points gives more complete coverage.

---

## What is different from production banking

| Area | Assignment | Production banking |
|---|---|---|
| Jenkins port | Open to 0.0.0.0/0 | Restricted to GitHub IP ranges |
| Image tag | Build number | Git SHA |
| Approval timeout | Default (infinite) | Time-limited (e.g. 2 hours) |
| Nexus | Not used | Required for artifact versioning |
| Server configuration | Manual | Ansible playbooks |
| Secret rotation | Not implemented | Automated via Secrets Manager |