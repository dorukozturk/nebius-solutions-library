---
sidebar_position: 2
---

# Generated Configuration Reference

This page is generated from `../wireguard/terraform.tfvars`.

Generation date: 2026-03-22

## tfvars catalog

## SSH config

### `ssh_user_name`

Username you want to use to connect to the nodes

Example from `terraform.tfvars`:

```hcl
ssh_user_name  = "" # Username you want to use to connect to the nodes
```

### `ssh_public_key`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
ssh_public_key = {
key  = "put your public ssh key here" OR
path = "put path to public ssh key here"
}
```

## Public IP config

### `public_ip_allocation_id`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
public_ip_allocation_id = ""
```

## Regeneration

Run from `website/` with:

```bash
node ./scripts/generate-flat-tfvars-docs.mjs --title "WireGuard" --source "../wireguard/terraform.tfvars" --output "./docs/wireguard/generated-configuration-reference.md"
```

