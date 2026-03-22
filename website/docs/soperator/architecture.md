---
sidebar_position: 2
---

# Soperator Architecture

`soperator` is organized as a Terraform composition that first creates the infrastructure layer and then configures the Slurm stack on top of Kubernetes.

The previous diagram was too detailed to be useful as a first-stop explanation. This page keeps the model intentionally simple.

## Simplified flow

```text
Terraform recipe
  -> shared storage and cluster infrastructure
  -> Nebius managed Kubernetes cluster
  -> Slurm operator and related services on Kubernetes
  -> login access and validation flows
```

## Control flow

The example installation wires together several modules:

- `filestore`
  - Creates or attaches shared filesystems for jail, controller spool, accounting, and optional submounts
- `k8s`
  - Provisions the Nebius managed Kubernetes cluster and fetches credentials into the local kubeconfig
- `slurm`
  - Applies the Slurm operator layer and related Helm or Flux-driven configuration
- `login`
  - Produces the connection helper used to reach the login endpoint
- cleanup and auxiliary modules
  - Handle post-destroy or operational cleanup paths

## Main runtime layers

### 1. Infrastructure and storage

Before Slurm is usable, the Terraform recipe prepares the underlying storage and cluster shape:

- jail filesystem
- optional extra data submounts
- optional accounting and NFS storage
- node role definitions and sizing

### 2. Managed Kubernetes cluster

The cluster itself is created by the `soperator/modules/k8s` module. It provisions:

- a managed control plane
- role-based node groups
- optional GPU-oriented node groups
- a public control plane endpoint
- kubeconfig context registration via `nebius mk8s cluster get-credentials`

### 3. Slurm services on Kubernetes

Slurm is not installed as a set of manually configured VMs. Instead, the repository treats Kubernetes as the substrate and places Slurm services on top of it through the `slurm` module.

This gives the solution:

- Kubernetes-native restart behavior
- separation between infrastructure provisioning and service release logic
- easier integration with observability and other platform services

### 4. Shared storage model

The documentation and example configuration revolve around a shared filesystem called the jail.

The jail is mounted across cluster roles and is used as the common environment surface for:

- controller nodes
- worker nodes
- login nodes

Additional filestore submounts can be attached for data-heavy use cases such as benchmark datasets.

## Node roles you should expect

The installation code and example variables model separate node sets for:

- system
- controller
- workers
- login
- optional accounting
- optional NFS

That separation matters because sizing, GPU attachment, autoscaling, storage, and public exposure choices differ by role.

## Access model

After deployment, two operational paths matter:

- Kubernetes access through the generated kubeconfig context
- Slurm access through the login endpoint or generated `login.sh` helper

The repo also stores a static IP allocation for SSH access into the Slurm environment.
