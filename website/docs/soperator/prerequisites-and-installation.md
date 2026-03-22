---
sidebar_position: 3
---

# Prerequisites and Installation

This page condenses the current `soperator/README.md` installation flow into a shorter operator path.

## Prerequisites

Install these tools before starting:

- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- [Nebius CLI](https://nebius.com/docs/cli/quickstart)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [jq](https://jqlang.github.io/jq/download/)
- `coreutils`
  - macOS: `brew install coreutils`
  - Ubuntu: `sudo apt-get install coreutils`

## Get the Terraform recipe

The repo README recommends two entry paths:

- download and unpack a released `soperator` Terraform archive
- check out a tagged release from Git

If you are already working in this repository, start from the repo root and move into `soperator`.

## Create an installation directory

```bash
cd soperator
export INSTALLATION_NAME=<your-name>
mkdir -p installations/$INSTALLATION_NAME
cd installations/$INSTALLATION_NAME
cp -r ../example/* ../example/.* .
```

## Load Nebius environment settings

Set `NEBIUS_TENANT_ID` and `NEBIUS_PROJECT_ID` in your `.envrc`, then load it:

```bash
source .envrc
```

The repo README describes this as doing several things:

- authenticating the Nebius CLI and exporting an IAM token
- creating or retrieving the service account used by Terraform
- preparing object storage access for Terraform state
- exporting resource IDs used by the recipe

Validate the token:

```bash
nebius iam whoami
```

## Decide how you will provide the jail filesystem

You have two patterns:

- create the jail outside Terraform and attach it by ID
- let Terraform create it as part of the installation

The current example configuration defaults to an existing filesystem reference.

If you create the filesystem manually, keep the warning from the original README in mind: attaching an existing filesystem directly as the jail can overwrite data unless you isolate usage with submounts.

![Create filesystem step 1](/img/soperator/create_fs_1.png)
![Create filesystem step 2](/img/soperator/create_fs_2.png)
![Create filesystem step 3](/img/soperator/create_fs_3.png)

## Edit `terraform.tfvars`

The minimum settings to review first are:

- `company_name`
- `production`
- `iam_merge_request_url`
- `filestore_jail`
- `slurm_nodeset_workers`
- `slurm_login_ssh_root_public_keys`

The example also exposes optional storage, accounting, NFS, observability, and node-local disk settings.

Example worker block:

```hcl
slurm_nodeset_workers = [{
  size                    = 2
  nodes_per_nodegroup     = 1
  max_unavailable_percent = 50
  resource = {
    platform = "gpu-h100-sxm"
    preset   = "8gpu-128vcpu-1600gb"
  }
  boot_disk = {
    type                 = "NETWORK_SSD"
    size_gibibytes       = 2048
    block_size_kibibytes = 4
  }
  gpu_cluster = {
    infiniband_fabric = ""
  }
}]
```

## Initialize and apply

```bash
terraform init
terraform apply
```

If you need multiple `soperator` clusters in the same Terraform state backend, create or select a workspace first:

```bash
terraform workspace list
terraform workspace new <my-cluster-name>
```

## Expected provisioning time

The current README estimates roughly 40 minutes for a small GPU cluster with two 8-GPU nodes.
