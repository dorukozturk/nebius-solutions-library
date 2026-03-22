---
sidebar_position: 4
---

# Prerequisites and Deployment

This page condenses the current `k8s-training/README.md` and `environment.sh` workflow into a shorter deployment path.

## Prerequisites

Install:

- [Nebius CLI](https://docs.nebius.ai/cli/install/)
- [Terraform](https://developer.hashicorp.com/terraform)
- [jq](https://jqlang.github.io/jq/download/)
- `kubectl`

The existing README also suggests reloading your shell after installing the Nebius CLI.

## Set environment variables

The bootstrap script expects:

- `NEBIUS_TENANT_ID`
- `NEBIUS_PROJECT_ID`
- `NEBIUS_REGION`

Then run:

```bash
source ./environment.sh
```

## What `environment.sh` does

The script prepares more than shell variables. It also:

- fetches an IAM token
- resolves a VPC subnet
- creates or reuses an object storage bucket for Terraform state
- creates or reuses a service account
- adds that service account to the `editors` group
- creates an access key for Terraform backend access
- writes `terraform_backend_override.tf`
- exports the required `TF_VAR_*` values

## Basic deployment flow

```bash
terraform init
terraform plan
terraform apply
```

Before `terraform apply`, edit `terraform.tfvars` and review:

- node counts and presets
- Filestore settings
- public endpoint exposure
- observability flags
- GPU operator and MIG settings

## Minimum configuration checklist

At a minimum, validate:

- SSH settings
- CPU node count and preset
- GPU node count and preset
- region and inferred defaults
- whether shared Filestore should be created or attached
- whether you want public endpoints or public node IPs

## Optional deployment paths

Enable these only when needed:

- KubeRay cluster or service deployment
- custom driver mode
- preemptible nodes
- egress gateway
- test mode for NCCL validation resources
