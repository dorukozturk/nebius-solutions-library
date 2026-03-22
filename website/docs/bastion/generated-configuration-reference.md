---
sidebar_position: 2
---

# Generated Configuration Reference

This page is generated from `../bastion/terraform.tfvars`.

Generation date: 2026-03-22

## tfvars catalog

## General

### `ssh_user_name`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
ssh_user_name = "bastion"
```

### `ssh_public_key`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
ssh_public_key = {
  key  = "put your public ssh key here"
  path = "put path to public ssh key here"
}
```

## Regeneration

Run from `website/` with:

```bash
node ./scripts/generate-flat-tfvars-docs.mjs --title "Bastion" --source "../bastion/terraform.tfvars" --output "./docs/bastion/generated-configuration-reference.md"
```

