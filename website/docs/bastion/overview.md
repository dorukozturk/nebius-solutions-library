---
sidebar_position: 1
---

# Bastion Overview

The `bastion` solution provisions a secure jump host for Nebius infrastructure.

## What it does

According to the repository README, it deploys:

- a bastion VM
- a service account and Nebius CLI configuration on the host
- WireGuard with a web UI
- `kubectl` configured against the first available managed Kubernetes cluster in the project

## Main use case

Use this solution when you want to reduce direct public exposure of the rest of your infrastructure and route administrative access through a single controlled host.

## Connect model

The README describes the typical SSH pattern:

- connect to the bastion using its public IP
- use `ProxyJump` to reach private targets behind it

## Configuration

Use the generated tfvars reference for the actual deployment inputs:

- [Generated configuration reference](./generated-configuration-reference.md)
