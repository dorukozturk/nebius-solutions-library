---
sidebar_position: 1
---

# K8s Training Overview

`k8s-training` provisions a Nebius managed Kubernetes cluster designed for AI and training workloads, with separate CPU and GPU node groups and optional platform add-ons.

## What it deploys

The Terraform recipe can provision:

- a Nebius managed Kubernetes cluster
- CPU and GPU node groups
- optional Filestore-backed shared storage
- Network Operator and GPU Operator integration
- Nebius observability components
- optional KubeRay deployment
- optional NCCL test resources in test mode

## Main use case

This solution is for teams that want a Kubernetes-native training cluster instead of a Slurm-on-Kubernetes stack.

Typical reasons to choose it:

- you want direct Kubernetes access for training jobs
- you need both CPU and GPU node pools
- you want GPU operator, networking, and observability integrated into the same recipe
- you may want to layer Ray workloads on top of the cluster

## How the recipe is structured

The main code lives under `k8s-training/` and is split roughly into:

- `main.tf`
  - managed cluster and node groups
- `helm.tf`
  - operators and observability modules
- `filesystem.tf`
  - Filestore create-or-attach logic
- `applications.tf`
  - optional KubeRay components
- `variables.tf`
  - deployment and feature controls
- `environment.sh`
  - bootstrap for Terraform backend and required environment values

## Reading order

1. Read [Architecture](./architecture.md)
2. Review [Configuration Reference](./configuration-reference.md)
3. Use [Generated Configuration Reference](./generated-configuration-reference.md) while editing `terraform.tfvars`
4. Follow [Prerequisites and Deployment](./prerequisites-and-deployment.md)
5. Finish with [Access, Storage, and Operations](./access-storage-and-operations.md)
