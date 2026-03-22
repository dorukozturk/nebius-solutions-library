---
sidebar_position: 2
---

# Generated Configuration Reference

This page is generated from `../nfs-server/terraform.tfvars`.

Generation date: 2026-03-22

## tfvars catalog

## General

### `parent_id`

The project-id in this context

Example from `terraform.tfvars`:

```hcl
parent_id      = "" # The project-id in this context
```

### `subnet_id`

Use the command "nebius vpc v1alpha1 network list" to see the subnet id

Example from `terraform.tfvars`:

```hcl
subnet_id      = "" # Use the command "nebius vpc v1alpha1 network list" to see the subnet id
```

### `region`

Project region

Example from `terraform.tfvars`:

```hcl
region         = "" # Project region
```

### `ssh_user_name`

Username you want to use to connect to the nodes

Example from `terraform.tfvars`:

```hcl
ssh_user_name  = "" # Username you want to use to connect to the nodes
```

### `ssh_public_keys`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
ssh_public_keys = [
  "ssh-rsa AAAA...", # First user's public key
  "ssh-rsa AAAA..."  # Second user's public key
]
```

### `nfs_ip_range`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
nfs_ip_range = "192.168.0.0/16"
```

### `disk_type`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
disk_type = "NETWORK_M3_IO"
```

### `number_raid_disks`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
number_raid_disks = 4
```

### `nfs_size`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
nfs_size = 93 * 1024 * 1024 * 1024
```

### `cpu_nodes_preset`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
cpu_nodes_preset = "16vcpu-64gb"
```

### `public_ip`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
public_ip = true
```

## Regeneration

Run from `website/` with:

```bash
node ./scripts/generate-flat-tfvars-docs.mjs --title "NFS" --source "../nfs-server/terraform.tfvars" --output "./docs/nfs-server/generated-configuration-reference.md"
```

