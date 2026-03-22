---
sidebar_position: 2
---

# Generated Configuration Reference

This page is generated from `../vm-instance/terraform.tfvars`.

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

### `preset`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
preset   = "1gpu-16vcpu-200gb"
```

### `platform`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
platform = "gpu-h200-sxm"
```

### `users`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
users = [
  {
    user_name    = "tux",
    ssh_key_path = "~/.ssh/id_rsa.pub"
  },
  {
    user_name      = "tux2",
    ssh_public_key = "<SSH KEY STRING>"
  }
]
```

### `public_ip`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
public_ip      = true
```

### `instance_count`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
instance_count = 2
```

### `preemptible`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
preemptible    = false
```

### `shared_filesystem_id`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
shared_filesystem_id = ""
```

### `mount_bucket`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
mount_bucket         = ""
```

### `fabric`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
fabric = "fabric-n"
```

## Regeneration

Run from `website/` with:

```bash
node ./scripts/generate-flat-tfvars-docs.mjs --title "VM" --source "../vm-instance/terraform.tfvars" --output "./docs/vm-instance/generated-configuration-reference.md"
```

