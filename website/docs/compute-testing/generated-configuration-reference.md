---
sidebar_position: 2
---

# Generated Configuration Reference

This page is generated from `../compute-testing/terraform.tfvars`.

Generation date: 2026-03-22

## tfvars catalog

## General

### `parent_id`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
parent_id         = ""
```

### `subnet_id`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
subnet_id         = ""
```

### `ssh_public_key`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
ssh_public_key = {
key  = "put your public ssh key here" OR
path = "put path to ssh key here"
}
```

## Regeneration

Run from `website/` with:

```bash
node ./scripts/generate-flat-tfvars-docs.mjs --title "Compute" --source "../compute-testing/terraform.tfvars" --output "./docs/compute-testing/generated-configuration-reference.md"
```

