---
sidebar_position: 1
---

# Soperator Overview

`soperator` deploys a Slurm environment on top of a Nebius managed Kubernetes cluster, using Terraform to provision infrastructure and install the Slurm operator stack.

## Why this solution exists

The repository positions `soperator` as a way to combine Slurm's HPC workflow model with Kubernetes primitives and managed Nebius infrastructure.

Key benefits called out in the repo:

- Fast scale-out and replacement of nodes
- Shared jail filesystem across cluster roles
- Isolation through containerized components
- Automated GPU-oriented operational checks

## What gets deployed

At a high level, the recipe provisions:

- A Nebius managed Kubernetes cluster
- Slurm-related components installed onto that cluster
- Role-specific node groups for system, controller, login, worker, and optional accounting or NFS responsibilities
- Shared storage for jail and optional submounts
- Access paths for both Kubernetes administration and Slurm login

The main installation entry point is the Terraform example under `soperator/installations/example`.

## Core building blocks

- `soperator/installations/example`
  - The user-facing installation recipe and example variable set
- `soperator/modules/k8s`
  - Managed Kubernetes cluster provisioning and credentials setup
- `soperator/modules/slurm`
  - Slurm-related release and configuration layer
- `soperator/modules/filestore`
  - Shared filesystems for jail, controller state, and accounting
- `soperator/modules/login`
  - Login workflow and connection helper assets
- `soperator/test`
  - Delivery scripts and validation material

## Suggested reading order

If you are new to this solution:

1. Read [Architecture](./architecture.md)
2. Use [Generated Configuration Reference](./generated-configuration-reference.md) while editing `terraform.tfvars`
3. Follow [Prerequisites and Installation](./prerequisites-and-installation.md)
4. Finish with [Access and Day-2 Operations](./access-and-day-2-operations.md) and [Testing and Validation](./testing-and-validation.md)
