# Terraform project standards

This document covers the structure decisions made for this project, the reasoning behind them, and how the project would evolve for a production banking platform with multiple environments.

---

## Current structure

```
terraform/
├── backend.tf
├── provider.tf
├── variables.tf
├── terraform.tfvars        (gitignored)
├── main.tf
├── outputs.tf
└── modules/
    ├── vpc/
    ├── security-groups/
    ├── eks/
    └── rds/
```

### What this gives us

- All infrastructure is defined as reusable modules
- Variables and outputs are in separate files — not mixed into `main.tf`
- State is remote — S3 with DynamoDB locking
- Provider versions are pinned via `.terraform.lock.hcl`
- Sensitive values live in `terraform.tfvars` which is never committed

This is a solid foundation for a single environment. For multiple environments it needs to evolve.

---

## The problem with a single root module

Right now all environment-specific values live in one `terraform.tfvars` file. If we want staging and production to be separate:

- Staging uses `t3.medium` nodes, 2 replicas, single AZ RDS
- Production uses `m5.xlarge` nodes, 3 replicas, Multi-AZ RDS

With the current structure you would need to swap out `terraform.tfvars` manually before every apply. One wrong apply against the wrong environment and you have changed production when you meant staging.

---

## Production-grade structure — environment directories

```
terraform/
├── modules/                    (unchanged — reusable modules)
│   ├── vpc/
│   ├── security-groups/
│   ├── eks/
│   └── rds/
│
└── environments/
    ├── staging/
    │   ├── backend.tf          (state key: staging/terraform.tfstate)
    │   ├── provider.tf
    │   ├── main.tf             (calls modules with staging values)
    │   ├── variables.tf
    │   ├── terraform.tfvars    (gitignored)
    │   └── outputs.tf
    │
    └── production/
        ├── backend.tf          (state key: production/terraform.tfstate)
        ├── provider.tf
        ├── main.tf             (calls modules with production values)
        ├── variables.tf
        ├── terraform.tfvars    (gitignored)
        └── outputs.tf
```

### What this gives us

Each environment has its own directory and its own state file in S3:

```
s3://8byte-terraform-state-prod/
├── staging/terraform.tfstate
└── production/terraform.tfstate
```

A `terraform apply` inside `environments/staging/` can never touch production infrastructure — they have completely separate state files, separate backends, and separate variable files. There is no way to accidentally apply staging values to production.

---

## Terraform workspaces — why we did not use them

Terraform has a built-in feature called workspaces. A workspace is a named instance of state — the same configuration can be applied with different state files by switching workspaces.

```bash
terraform workspace new staging
terraform workspace new production
terraform workspace select staging
terraform apply
```

### Why workspaces were not used here

Workspaces share the same `terraform.tfvars` file and the same `main.tf`. Switching environments means switching workspace — not switching directories. There is no structural separation.

The community consensus is that workspaces are suitable for testing small differences in the same environment. They are not suitable for managing genuinely different environments like staging and production. The Terraform documentation itself notes:

> Workspaces alone are not a sufficient mechanism for separating environments with different configurations.

The environment directory approach is the pattern recommended by HashiCorp for production use.

---

## State file separation — what the S3 keys look like

### Current (single root module)

```
s3://8byte-terraform-state-prod/infra/terraform.tfstate
```

### Production-grade (environment directories)

```
s3://8byte-terraform-state-prod/staging/terraform.tfstate
s3://8byte-terraform-state-prod/production/terraform.tfstate
```

Each environment's `backend.tf` specifies its own key:

```hcl
# environments/staging/backend.tf
backend "s3" {
  bucket         = "8byte-terraform-state-prod"
  key            = "staging/terraform.tfstate"
  region         = "ap-south-1"
  dynamodb_table = "8byte-terraform-lock"
  encrypt        = true
}

# environments/production/backend.tf
backend "s3" {
  bucket         = "8byte-terraform-state-prod"
  key            = "production/terraform.tfstate"
  region         = "ap-south-1"
  dynamodb_table = "8byte-terraform-lock"
  encrypt        = true
}
```

---

## How module reuse works across environments

Modules in `modules/` do not change. Only the values passed to them differ per environment.

```hcl
# environments/staging/main.tf
module "eks" {
  source             = "../../modules/eks"
  node_instance_type = "t3.medium"
  node_desired_size  = 2
  node_min_size      = 2
  node_max_size      = 4
}

# environments/production/main.tf
module "eks" {
  source             = "../../modules/eks"
  node_instance_type = "m5.xlarge"
  node_desired_size  = 3
  node_min_size      = 3
  node_max_size      = 9
}
```

The module code is identical. The inputs are different. This is the correct separation of concerns.

---

## Why this was not implemented for the assignment

Implementing two full environment directories would double the Terraform code in the repository and also require running `terraform apply` twice — once for staging, once for production — each creating real AWS resources that cost money.

For the assignment, a single environment (`prod`) with a single root module demonstrates all the key concepts:

- Modular structure
- Remote state
- State locking
- Variable separation
- Output separation

The environment directory pattern is documented here so the reviewer can see the understanding exists — and it would be the first refactor applied before this project went into production.

---

## Summary — what we implemented vs what production looks like

| Practice | Assignment | Production |
|---|---|---|
| Modular structure | Yes | Yes |
| Remote state | Yes — S3 | Yes — S3 |
| State locking | Yes — DynamoDB | Yes — DynamoDB |
| Variable separation | Yes — tfvars | Yes — per-env tfvars |
| Output separation | Yes | Yes |
| Environment isolation | Single env | Environment directories |
| State isolation | Single state file | Per-environment state files |
| Workspaces | Not used | Not used — env dirs preferred |
| Lock file committed | Yes | Yes |
| Secrets in tfvars | No — gitignored | No — gitignored |