# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Terraform IaC for a **Grafana Loki** logging stack on AWS, designed as a cheaper alternative to CloudWatch Logs (target: ~5 TB logs/day across ECS, EC2, Kubernetes, and non-AWS servers). This is a take-home assignment: phase 1 is the written design, phase 2 is a minimal working PoC. The design rationale, cost analysis, and requirements-to-solution mapping live in `README.md` and `docs/` (in Czech). Read `docs/deleteme.md` for the full architecture writeup before making infra decisions.

All infrastructure is in **eu-central-1** (Frankfurt). AWS provider pinned to `~> 6.0`.

## Two separate Terraform root modules

Order matters — `tf-bootstrap/` must be applied before `loki/` can init its backend.

- **`tf-bootstrap/`** — Creates the versioned S3 bucket (`terraform-state-0sl22y554u`) that holds remote state for everything else. Uses **local state** (its own `terraform.tfstate` is committed). Apply once, rarely touched.
- **`loki/`** — The actual Loki infrastructure (currently the S3 bucket for chunks + TSDB index). Uses the **S3 backend** (`backend "s3"` in `loki/provider.tf`) with `use_lockfile = true` for state locking. This is where ongoing work happens.

Each directory is an independent Terraform working directory — `terraform init/plan/apply` must be run from inside the relevant one.

## Commands

```bash
# Bootstrap (first time only, from tf-bootstrap/)
cd tf-bootstrap && terraform init && terraform apply

# Day-to-day work (from loki/)
cd loki && terraform init
terraform plan
terraform validate
terraform apply
```

## Design guidelines

Do not write code for the user, always provide enough guidance and documentation sources for user to write everything himself and understand every single line of code.
