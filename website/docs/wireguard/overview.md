---
sidebar_position: 1
---

# WireGuard Overview

The `wireguard` solution provisions a jump server with WireGuard installed so external systems can securely reach Nebius-hosted resources.

## What it does

The repository README frames this as a bridge between:

- a secure zone inside Nebius AI Cloud
- a DMZ or external network outside Nebius AI Cloud

This allows encrypted access with a single public IP on the WireGuard host.

## Main use case

Use this when you need a lightweight VPN-style access path into private Nebius infrastructure without assigning public IPs to every machine.

## Configuration

The main user-facing deployment values are documented from `wireguard/terraform.tfvars` here:

- [Generated configuration reference](./generated-configuration-reference.md)
