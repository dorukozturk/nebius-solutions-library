---
sidebar_position: 2
---

# Generated Configuration Reference

This page is generated from `../dsvm/terraform.tfvars`.

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
region         = "eu-north1" # Project region
```

### `ssh_user_name`

Username you want to use to connect to the nodes

Example from `terraform.tfvars`:

```hcl
ssh_user_name  = "ubuntu" # Username you want to use to connect to the nodes
```

### `ssh_public_key`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
ssh_public_key = {
  key  = "put your public ssh key here"
  path = "put path to ssh key here"
}
```

## Regeneration

Run from `website/` with:

```bash
node ./scripts/generate-flat-tfvars-docs.mjs --title "DSVM" --source "../dsvm/terraform.tfvars" --output "./docs/dsvm/generated-configuration-reference.md"
```

