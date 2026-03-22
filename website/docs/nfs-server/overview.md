---
sidebar_position: 1
---

# NFS Server Overview

The `nfs-server` solution provisions an NFS server on Nebius Cloud using a VM plus attached storage.

## What it does

The module creates:

- a virtual machine
- one or more data disks
- an exported NFS share

The README then shows how to mount that share from client systems.

## Main use case

Use this when you need a simple shared file server for workloads that expect NFS instead of object storage or Filestore integration.

## Configuration

The deployment values from `nfs-server/terraform.tfvars` are documented here:

- [Generated configuration reference](./generated-configuration-reference.md)
