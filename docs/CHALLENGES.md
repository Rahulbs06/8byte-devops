# Challenges faced

This document covers real issues encountered during the implementation of the 8byte banking platform infrastructure, how each was resolved, and what to do differently next time.

---

## 1. Root user access keys in use

**What happened**

Started with AWS root user access keys configured in the local AWS CLI. Realised this only after beginning the Terraform setup.

**Why it matters**

Root user has unrestricted access to the entire AWS account including billing, account closure, and all services. A leaked root key means complete account compromise with no recovery path.

**Resolution**

Created a dedicated IAM user `terraform-deployer` with `AdministratorAccess` policy. Reconfigured AWS CLI with the new user credentials. Deactivated all root access keys — root is now console-only.

**Next time**

Never generate root access keys. On a fresh AWS account, the first action should always be to create an IAM user and enable MFA on root before doing anything else.

---

## 2. Terraform remote state — chicken and egg problem

**What happened**

`backend.tf` references an S3 bucket and DynamoDB table that don't exist yet. Running `terraform init` before creating them fails immediately.

**Why it matters**

Without remote state, Terraform state is stored locally. If the local machine is lost, the entire infrastructure becomes unmanageable — you cannot update or destroy resources without the state file.

**Resolution**

Created a separate `bootstrap/` Terraform module that uses local state intentionally. This module creates only the S3 bucket and DynamoDB table. Once applied, the main `terraform/` directory points to that bucket as its backend. Everything is code — no AWS CLI commands needed.

**Next time**

Always start a new project with a bootstrap module. Never create state infrastructure manually or via CLI scripts.

---

## 3. GitHub authentication failure — password no longer accepted

**What happened**

Running `git push` failed with authentication error. GitHub deprecated password-based Git authentication in 2021.

**Resolution**

Generated a Personal Access Token (PAT) from GitHub Settings → Developer settings → Tokens (classic) with `repo` and `workflow` scopes. Updated the remote URL to include the token:

```
git remote set-url origin https://USERNAME:TOKEN@github.com/repo.git
```

**Next time**

On any new machine, configure Git with a PAT immediately. Consider using SSH keys instead — they don't expire and don't need to be embedded in URLs.

---

## 4. `.tfvars` and `.terraform.lock.hcl` mixed up in `.gitignore`

**What happened**

Added `.terraform.lock.hcl` to `.gitignore` along with `.tfvars`. This was wrong — the lock file should be committed to Git so all team members use the exact same provider versions. The `.tfvars` file should never be committed because it contains environment-specific values and potentially sensitive data.

**Resolution**

Removed `.terraform.lock.hcl` from `.gitignore`. Force-added it to the repo using `git add -f`. Kept `*.tfvars` in `.gitignore`.

**Next time**

`.gitignore` for Terraform projects should always be:
```
*.tfvars
*.tfstate
*.tfstate.backup
.terraform/
crash.log
```
Never add `.terraform.lock.hcl` to `.gitignore`.

---

## 5. NAT Gateway cost — 3 vs 1

**What happened**

Initial design used one NAT Gateway per AZ (3 total) for high availability. Each NAT Gateway costs approximately $32/month plus data transfer. Three NAT Gateways add up to ~$96/month just for outbound routing.

**Resolution**

Reduced to a single NAT Gateway in the first AZ for the assignment. All three private subnets route outbound traffic through this single gateway.

**Production note**

A single NAT Gateway is a single point of failure for outbound internet access. If `ap-south-1a` goes down, nodes in `ap-south-1b` and `ap-south-1c` lose outbound connectivity — they cannot pull images from ECR or call external APIs. For a production banking platform, one NAT Gateway per AZ is non-negotiable.

**Next time**

Make NAT Gateway count a variable with a clear comment explaining the cost vs availability tradeoff. Default to 1 for development environments, 3 for production.

---

## 6. EKS version 1.29 AMI not available in ap-south-1

**What happened**

Specified `cluster_version = "1.29"` in `terraform.tfvars`. The EKS cluster was created successfully but the node group creation failed — AWS could not find a supported AMI for Kubernetes 1.29 in the `ap-south-1` region for `t3.medium` instances.

**Resolution**

Destroyed the existing EKS cluster using `terraform destroy -target=module.eks.aws_eks_cluster.main` and recreated it with version `1.31`. Node group creation succeeded immediately.

**Next time**

Before specifying a Kubernetes version, verify which versions are available in the target region:
```
aws eks describe-addon-versions --region ap-south-1 --query 'addons[0].addonVersions[0].compatibilities[*].clusterVersion'
```
Always use the latest stable version unless there is a specific reason to pin an older one.

---

## 7. Security group — invalid protocol and port combination

**What happened**

Defined an EKS nodes security group ingress rule with `protocol = "-1"` (all traffic) and `from_port = 0`, `to_port = 65535`. Terraform apply failed with:

```
from_port (0) and to_port (65535) must both be 0 to use the 'ALL' "-1" protocol
```

**Resolution**

When `protocol = "-1"`, both `from_port` and `to_port` must be set to `0`. Changed the rule to `from_port = 0, to_port = 0, protocol = "-1"`.

**Next time**

Protocol `-1` means all traffic — specifying a port range alongside it is contradictory. Use `from_port = 0, to_port = 0` when the intent is to allow all traffic.

---

## 8. AWS resource names cannot start with a number

**What happened**

Project name is `8byte`. Resources named `${var.project_name}-${var.environment}-postgres` produced `8byte-prod-postgres` as the RDS identifier. AWS rejected this:

```
first character of "identifier" must be a letter
```

Same issue occurred with the RDS DB subnet group name.

**Resolution**

Hardcoded the prefix `eightbyte-` for RDS identifier and subnet group name:
```
identifier = "eightbyte-${var.environment}-postgres"
name       = "eightbyte-${var.environment}-db-subnet-group"
```

**Next time**

When a project name starts with a number, define a separate `resource_prefix` variable that starts with a letter. Apply this prefix to all resource identifiers consistently instead of fixing it case by case.

---

## 9. PostgreSQL version not available in ap-south-1

**What happened**

Specified `engine_version = "15.5"`. Apply failed:
```
Cannot find version 15.5 for postgres
```
Tried `15.4` — same error. AWS does not host every minor version in every region.

**Resolution**

Listed available versions using AWS CLI:
```
aws rds describe-db-engine-versions --engine postgres --region ap-south-1 --query "DBEngineVersions[*].EngineVersion"
```
Used `15.10` which was available and recent.

**Next time**

Before specifying any engine version in Terraform, always verify availability in the target region using the above command. Do not assume a version is available just because it exists globally.

---

## 10. Manual ALB conflicting with EKS ingress controller

**What happened**

Created an ALB manually via Terraform as a separate module. Later realised that when an Ingress object is created in Kubernetes, the AWS Load Balancer Controller automatically creates and manages its own ALB. Having both a manually-created ALB and an ingress-managed ALB creates two separate load balancers — wasted cost and routing confusion.

**Resolution**

Destroyed the manually created ALB, removed the `alb` module from the codebase, and removed all references from `main.tf` and `outputs.tf`. The ALB will be created automatically by the EKS ingress controller when the application is deployed in Phase 2.

**Next time**

When using EKS, never create an ALB manually. The AWS Load Balancer Controller handles ALB lifecycle entirely based on Ingress objects. The only Terraform work needed for ALB on EKS is the IAM role for the controller — not the ALB itself.

---

## 11. Non-ASCII characters in AWS resource descriptions

**What happened**

Used an em dash `—` in a security group description:
```
"Security group for RDS — allow only from EKS nodes"
```
AWS rejected this with:
```
Value for parameter GroupDescription is invalid. Character sets beyond ASCII are not supported.
```

**Resolution**

Replaced `—` (em dash, Unicode U+2014) with `-` (regular hyphen, ASCII 0x2D).

**Next time**

Stick to plain ASCII in all AWS resource names, descriptions, and tags. Avoid smart quotes, em dashes, accented characters, or any character outside the standard 7-bit ASCII range.

---

## 12. VS Code silently saving empty files

**What happened**

Created new `.tf` files in VS Code and pasted content, but some files saved as empty. This caused repeated `Unsupported argument` errors in Terraform because the module variables were not being loaded.

**Resolution**

Switched to writing files directly from the terminal using `cat > filename << 'ENDOFFILE'` syntax. Verified content using `cat filename` before running Terraform commands.

**Next time**

After creating any new Terraform file in VS Code, always verify the content using `cat` in the terminal before running `terraform plan`. Never assume the file saved correctly just because VS Code showed no error.

---

## 13. kubectl not installed on Windows

**What happened**

After EKS cluster was created and kubeconfig was updated, running `kubectl get nodes` failed with `command not found`.

**Resolution**

Downloaded `kubectl.exe` for Windows using `curl.exe`:
```
curl.exe -LO "https://dl.k8s.io/release/v1.31.0/bin/windows/amd64/kubectl.exe"
```
Could not move to `System32` due to permission restrictions. Created `C:\Users\rahul\bin\` and added it to `PATH` using `export PATH=$PATH:/c/Users/rahul/bin`.

**Next time**

Install kubectl, helm, and all required tools before starting the project. Maintain a tools checklist: AWS CLI, Terraform, kubectl, Helm, Docker, Git. Verify all are installed and working before writing a single line of infrastructure code.

---

## 14. EKS public endpoint left open

**What happened**

EKS cluster was created with the default configuration — public API endpoint enabled, private endpoint disabled. This means the Kubernetes API server was reachable from any IP on the internet.

**Resolution**

Updated the `vpc_config` block to enable private endpoint access:
```hcl
endpoint_private_access = true
endpoint_public_access  = true
```

**Production note**

For a banking platform, `endpoint_public_access` should be `false`. kubectl access should go through a VPN or bastion host inside the VPC. Public endpoint is kept enabled here only because the assignment is run from a local machine outside the VPC.

**Next time**

Always explicitly set both `endpoint_private_access` and `endpoint_public_access` in the EKS cluster configuration. Do not rely on AWS defaults.
