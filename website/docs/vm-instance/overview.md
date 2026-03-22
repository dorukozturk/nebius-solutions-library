---
sidebar_position: 1
---

# VM Instance Overview

The `vm-instance` solution provisions one or more Nebius VM instances with optional shared storage, S3 mounting, multiple users, and GPU cluster placement.

## What it supports

Based on the README, the recipe can:

- create multiple VMs
- assign public or private networking
- add multiple SSH users
- attach a shared filesystem
- mount an S3 bucket
- attach extra storage
- place GPU VMs into a fabric-backed cluster for InfiniBand connectivity

## Main use case

Use this when you want a flexible raw VM deployment pattern rather than a higher-level cluster solution.

## Configuration

The deployment values from `vm-instance/terraform.tfvars` are documented here:

- [Generated configuration reference](./generated-configuration-reference.md)
