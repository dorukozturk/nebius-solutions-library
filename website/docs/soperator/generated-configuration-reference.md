---
sidebar_position: 5
---

# Generated Configuration Reference

This page is generated from `soperator/installations/example/terraform.tfvars` comments plus resource metadata in `soperator/modules/available_resources`.

Generation date: 2026-03-22

## Why this page exists

- The example `terraform.tfvars` already contains operator guidance worth preserving.
- The Terraform resource metadata adds useful context for platforms, presets, and GPU-cluster capability.
- This page is meant to stay close to the repo instead of becoming a manually curated summary that drifts.

## Platform and preset catalog

### `cpu-e2`

- Regions: `eu-north1`
- Presets:
  - `2vcpu-8gb`: 2 vCPU, 8 GiB RAM, 0 GPU
  - `4vcpu-16gb`: 4 vCPU, 16 GiB RAM, 0 GPU
  - `8vcpu-32gb`: 8 vCPU, 32 GiB RAM, 0 GPU
  - `16vcpu-64gb`: 16 vCPU, 64 GiB RAM, 0 GPU
  - `32vcpu-128gb`: 32 vCPU, 128 GiB RAM, 0 GPU
  - `48vcpu-192gb`: 48 vCPU, 192 GiB RAM, 0 GPU
  - `64vcpu-256gb`: 64 vCPU, 256 GiB RAM, 0 GPU
  - `80vcpu-320gb`: 80 vCPU, 320 GiB RAM, 0 GPU

### `cpu-d3`

- Regions: `eu-north1`, `eu-north2`, `eu-west1`, `me-west1`, `uk-south1`, `us-central1`
- Presets:
  - `2vcpu-8gb`: 2 vCPU, 8 GiB RAM, 0 GPU
  - `4vcpu-16gb`: 4 vCPU, 16 GiB RAM, 0 GPU
  - `8vcpu-32gb`: 8 vCPU, 32 GiB RAM, 0 GPU
  - `16vcpu-64gb`: 16 vCPU, 64 GiB RAM, 0 GPU
  - `32vcpu-128gb`: 32 vCPU, 128 GiB RAM, 0 GPU
  - `48vcpu-192gb`: 48 vCPU, 192 GiB RAM, 0 GPU
  - `64vcpu-256gb`: 64 vCPU, 256 GiB RAM, 0 GPU
  - `96vcpu-384gb`: 96 vCPU, 384 GiB RAM, 0 GPU
  - `128vcpu-512gb`: 128 vCPU, 512 GiB RAM, 0 GPU
  - `160vcpu-640gb`: 160 vCPU, 640 GiB RAM, 0 GPU
  - `192vcpu-768gb`: 192 vCPU, 768 GiB RAM, 0 GPU
  - `224vcpu-896gb`: 224 vCPU, 896 GiB RAM, 0 GPU
  - `256vcpu-1024gb`: 256 vCPU, 1024 GiB RAM, 0 GPU

### `gpu-h100-sxm`

- Regions: `eu-north1`
- Presets:
  - `1gpu-16vcpu-200gb`: 16 vCPU, 200 GiB RAM, 1 GPU
  - `8gpu-128vcpu-1600gb`: 128 vCPU, 1600 GiB RAM, 8 GPU, GPU-cluster compatible

### `gpu-h200-sxm`

- Regions: `eu-north1`, `eu-north2`, `eu-west1`, `us-central1`
- Presets:
  - `1gpu-16vcpu-200gb`: 16 vCPU, 200 GiB RAM, 1 GPU
  - `8gpu-128vcpu-1600gb`: 128 vCPU, 1600 GiB RAM, 8 GPU, GPU-cluster compatible

### `gpu-b200-sxm`

- Regions: `us-central1`
- Presets:
  - `1gpu-20vcpu-224gb`: 20 vCPU, 224 GiB RAM, 1 GPU
  - `8gpu-160vcpu-1792gb`: 160 vCPU, 1792 GiB RAM, 8 GPU, GPU-cluster compatible

### `gpu-b200-sxm-a`

- Regions: `me-west1`
- Presets:
  - `1gpu-20vcpu-224gb`: 20 vCPU, 224 GiB RAM, 1 GPU
  - `8gpu-160vcpu-1792gb`: 160 vCPU, 1792 GiB RAM, 8 GPU, GPU-cluster compatible

### `gpu-b300-sxm`

- Regions: `uk-south1`
- Presets:
  - `1gpu-24vcpu-346gb`: 24 vCPU, 346 GiB RAM, 1 GPU
  - `8gpu-192vcpu-2768gb`: 192 vCPU, 2768 GiB RAM, 8 GPU, GPU-cluster compatible

## Variable catalog

## General

### `company_name`

Name of the company. It is used for context name of the cluster in .kubeconfig file.

Example from `terraform.tfvars`:

```hcl
company_name = ""
```

### `production`

Whether the cluster is production or not.

Example from `terraform.tfvars`:

```hcl
production = true
```

### `iam_merge_request_url`

Follow the installation guide and put IAM merge request URL here.
Required if production = true.

Example from `terraform.tfvars`:

```hcl
iam_merge_request_url = ""
```

## Infrastructure / Storage

### `controller_state_on_filestore`

Whether to store the controller state on filestore or network SSD.

Example from `terraform.tfvars`:

```hcl
controller_state_on_filestore = false
```

### `filestore_controller_spool`

Shared filesystem to be used on controller nodes.
Deprecated: Starting with version 1.22, this variable isn't used, as controller state is stored on network SSD disks.
Remains for the backward compatibility.

Example from `terraform.tfvars`:

```hcl
filestore_controller_spool = {
  spec = {
    size_gibibytes       = 128
    block_size_kibibytes = 4
  }
}
```

### `filestore_jail`

Shared filesystem to be used on controller, worker, and login nodes.
Notice that auto-backups are enabled for filesystems with size less than 12 TiB.
If you need backups for jail larger than 12 TiB, set 'backups_enabled' to 'force_enable' down below.

Example from `terraform.tfvars`:

```hcl
filestore_jail = {
  existing = {
    id = "computefilesystem-<YOUR-FILESTORE-ID>"
  }
}
```

### `filestore_jail_submounts`

Additional shared filesystems to be mounted inside jail.
If a big filesystem is needed it's better to deploy this additional storage because jails bigger than 12 TiB
ARE NOT BACKED UP by default.

Example from `terraform.tfvars`:

```hcl
filestore_jail_submounts = [{
  name       = "data"
  mount_path = "/mnt/data"
  existing = {
    id = "computefilesystem-<YOUR-FILESTORE-ID>"
  }
}]
```

### `node_local_jail_submounts`

Additional (Optional) node-local Network-SSD disks to be mounted inside jail on worker nodes.
It will create compute disks with provided spec for each node via CSI.
NOTE: in case of `NETWORK_SSD_NON_REPLICATED` disk type, `size` must be divisible by 93Gi - https://docs.nebius.com/compute/storage/types#disks-types.

Example from `terraform.tfvars`:

```hcl
node_local_jail_submounts = [{
  name            = "local-data"
  mount_path      = "/mnt/local-data"
  size_gibibytes  = 1024
  disk_type       = "NETWORK_SSD"
  filesystem_type = "ext4"
}]
```

### `node_local_image_disk`

Whether to create extra NRD disks for storing Docker/Enroot images and container filesystems on each worker node.
It will create compute disks with provided spec for each node via CSI.
NOTE: In case you're not going to use Docker/Enroot in your workloads, it's worth disabling this feature.
NOTE: `size` must be divisible by 93Gi - https://docs.nebius.com/compute/storage/types#disks-types.

Example from `terraform.tfvars`:

```hcl
node_local_image_disk = {
  enabled = true
  spec = {
    size_gibibytes  = 930
    filesystem_type = "ext4"
    # Could be changed to `NETWORK_SSD_NON_REPLICATED`
    disk_type = "NETWORK_SSD_IO_M3"
  }
}
```

### `filestore_accounting`

Shared filesystem to be used for accounting DB.
By default, null.
Required if accounting_enabled is true.

Example from `terraform.tfvars`:

```hcl
filestore_accounting = {
  spec = {
    size_gibibytes       = 512
    block_size_kibibytes = 4
  }
}
```

## Infrastructure / nfs-server

### `nfs_in_k8s`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
nfs_in_k8s = {
  enabled         = true
  version         = "1.2.0"
  use_stable_repo = true
  size_gibibytes  = 3720
  disk_type       = "NETWORK_SSD_IO_M3"
  filesystem_type = "ext4"
  threads         = 32 # to match preset in slurm_nodeset_nfs
}
```

## Infrastructure / Slurm

### `slurm_operator_version`

Version of soperator.

Example from `terraform.tfvars`:

```hcl
slurm_operator_version = "3.0.2"
```

### `slurm_operator_stable`

Is the version of soperator stable or not.

Example from `terraform.tfvars`:

```hcl
slurm_operator_stable = true
```

### `slurm_nodesets_partitions`

Each partition must have either is_all = true (includes all nodesets) or nodeset_refs (list of specific nodesets).
Users must not remove the "hidden" partition.
Users can modify the "main" partition, but should not remove it (there must be at least one default partition).

Example from `terraform.tfvars`:

```hcl
slurm_nodesets_partitions = [
  {
    name         = "main"
    is_all       = true
    nodeset_refs = [] # e.g. ["worker"], but is_all must be false in this case
    config       = "Default=YES PriorityTier=10 MaxTime=INFINITE State=UP OverSubscribe=YES"
  },
  {
    name         = "hidden"
    is_all       = true
    nodeset_refs = []
    config       = "Default=NO PriorityTier=10 PreemptMode=OFF Hidden=YES MaxTime=INFINITE State=UP OverSubscribe=YES"
  },
]
```

### `slurm_partition_config_type`

Type of the Slurm partition config. Could be either `default` or `custom`.
By default, "default".

Example from `terraform.tfvars`:

```hcl
slurm_partition_config_type = "default"
```

## Infrastructure / Slurm / Nodes

### `slurm_nodeset_system`

Configuration of System node set for system resources created by Soperator.
Keep in mind that the k8s nodegroup will have auto-scaling enabled and the actual number of nodes depends on the size
of the cluster.

Example from `terraform.tfvars`:

```hcl
slurm_nodeset_system = {
  min_size = 3
  max_size = 9
  resource = {
    platform = "cpu-d3"
    preset   = "8vcpu-32gb"
  }
  boot_disk = {
    type                 = "NETWORK_SSD"
    size_gibibytes       = 192
    block_size_kibibytes = 4
  }
}
```

### `slurm_nodeset_controller`

Configuration of Slurm Controller node set.

Example from `terraform.tfvars`:

```hcl
slurm_nodeset_controller = {
  size = 1
  resource = {
    platform = "cpu-d3"
    preset   = "16vcpu-64gb"
  }
  boot_disk = {
    type                 = "NETWORK_SSD"
    size_gibibytes       = 256
    block_size_kibibytes = 4
  }
}
```

### `slurm_nodeset_workers`

Configuration of Slurm Worker node sets.
Multiple worker nodesets are supported with different hardware configurations.
Each nodeset will be automatically split into node groups of max 100 nodes with autoscaling enabled.
infiniband_fabric is required field for GPU clusters

Example from `terraform.tfvars`:

```hcl
slurm_nodeset_workers = [
  {
    name = "worker"
    size = 128
    # Autoscaling configuration. Set enabled = false to use fixed node count instead.
    autoscaling = {
      enabled = true
      # min_size options:
      # - null: min=max, no scale-down (default, recommended - saves ~10 min on initial provisioning)
      #   it can be changed to a number later if needed.
      # - N: can scale down to N nodes
      min_size = null
    }
    resource = {
      platform = "gpu-h100-sxm"
      preset   = "8gpu-128vcpu-1600gb"
    }
    boot_disk = {
      type                 = "NETWORK_SSD"
      size_gibibytes       = 512
      block_size_kibibytes = 4
    }
    gpu_cluster = {
      infiniband_fabric = ""
    }
    # Change to preemptible = {} in case you want to use preemptible nodes
    preemptible = null
    # Use reservation_policy to leverage compute reservations (capacity blocks)
    # reservation_policy = {
    #   policy          = "AUTO"  # AUTO, FORBID, or STRICT
    #   reservation_ids = ["capacityblockgroup-xYYzzzzzz"]
    # }
    # Provide a list of strings to set Slurm Node features
    features = null
    # Set to `true` to create partition for the NodeSet by default
    create_partition = null
    # Whether to enable ephemeral nodes behavior for this worker nodeset.
    # When true, nodes will use dynamic topology injection and power management.
    # By default, false.
    ephemeral_nodes = false
    # Optional local NVMe passthrough for this nodeset only.
    # Uses local instance disks, creates a RAID0 array and mounts it on the host via cloud-init.
    # mount_path: path used for both host RAID mount and jail submount.
    # local_nvme = {
    #   enabled         = true
    #   mount_path      = "/mnt/local-nvme"
    #   filesystem_type = "ext4"
    # }
  },
]
```

### `use_preinstalled_gpu_drivers`

Driverfull mode is used to run Slurm jobs with GPU drivers installed on the worker nodes.

Example from `terraform.tfvars`:

```hcl
use_preinstalled_gpu_drivers = true
```

### `slurm_nodeset_login`

Configuration of Slurm Login node set.

Example from `terraform.tfvars`:

```hcl
slurm_nodeset_login = {
  size = 2
  resource = {
    platform = "cpu-d3"
    preset   = "32vcpu-128gb"
  }
  boot_disk = {
    type                 = "NETWORK_SSD"
    size_gibibytes       = 256
    block_size_kibibytes = 4
  }
}
```

### `slurm_nodeset_accounting`

Configuration of Slurm Accounting node set.
Required in case of Accounting usage.
By default, null.

Example from `terraform.tfvars`:

```hcl
slurm_nodeset_accounting = {
  resource = {
    platform = "cpu-d3"
    preset   = "8vcpu-32gb"
  }
  boot_disk = {
    type                 = "NETWORK_SSD"
    size_gibibytes       = 128
    block_size_kibibytes = 4
  }
}
```

### `slurm_nodeset_nfs`

Configuration of NFS node set.

Example from `terraform.tfvars`:

```hcl
slurm_nodeset_nfs = {
  size = 1
  resource = {
    platform = "cpu-d3"
    preset   = "32vcpu-128gb"
  }
  boot_disk = {
    type                 = "NETWORK_SSD"
    size_gibibytes       = 128
    block_size_kibibytes = 4
  }
}
```

## Infrastructure / Slurm / Nodes / Login

### `slurm_login_public_ip`

Public or private ip for login node load balancer
By default, true (public).

Example from `terraform.tfvars`:

```hcl
slurm_login_public_ip = true
```

### `tailscale_enabled`

Whether to enable Tailscale init container on login pod.
By default, false

Example from `terraform.tfvars`:

```hcl
tailscale_enabled = false
```

### `slurm_sssd_enabled`

Whether to enable the SSSD sidecar on Slurm controller, login, and worker nodes.
By default, false

Example from `terraform.tfvars`:

```hcl
slurm_sssd_enabled = false
```

### `slurm_sssd_conf_secret_ref_name`

Name of Secret containing sssd.conf for controller, login, and worker sssd containers.
By default, empty

Example from `terraform.tfvars`:

```hcl
slurm_sssd_conf_secret_ref_name = ""
```

### `slurm_sssd_ldap_ca_config_map_ref_name`

Name of ConfigMap containing LDAP CA certificates for controller, login, and worker sssd containers.
By default, empty

Example from `terraform.tfvars`:

```hcl
slurm_sssd_ldap_ca_config_map_ref_name = ""
```

### `slurm_login_ssh_root_public_keys`

Authorized keys accepted for connecting to Slurm login nodes via SSH as 'root' user.

Example from `terraform.tfvars`:

```hcl
slurm_login_ssh_root_public_keys = [
  "",
]
```

## Infrastructure / Slurm / Nodes / Exporter

### `slurm_exporter_enabled`

Whether to enable Slurm metrics exporter.
By default, true.

Example from `terraform.tfvars`:

```hcl
slurm_exporter_enabled = true
```

## Infrastructure / Slurm / Nodes / ActiveChecks

### `active_checks_scope`

Scope of active health-checks. Defines what checks should run after the cluster is provisioned.
Available scopes:
- "prod_acceptance" - run all available health-checks. Takes additional 30 minutes (H100) - 2 hours (B300).
- "prod_quick" - run all health-checks except those that take long. Takes additional 10 minutes (H100) - 30 minutes (B300).
- "testing" - to be used for Soperator E2E tests.
- "dev" - to be used for Soperator development clusters.
- "essential" - skip most of checks and run only essential ones. Don't use in production.

Example from `terraform.tfvars`:

```hcl
active_checks_scope = ""
```

## Infrastructure / Slurm / Config

### `slurm_shared_memory_size_gibibytes`

Shared memory size for Slurm controller and worker nodes in GiB.
By default, 64.

Example from `terraform.tfvars`:

```hcl
slurm_shared_memory_size_gibibytes = 1024
```

### `maintenance_ignore_node_groups`

Node groups that Soperator should ignore during maintenance events.
These ignored maintenance events will be handled by mk8s control plane instead.
Supported values: controller, nfs, system, login, accounting.

Example from `terraform.tfvars`:

```hcl
maintenance_ignore_node_groups = ["controller", "nfs"]
```

## Infrastructure / Slurm / Telemetry

### `telemetry_enabled`

Whether to enable telemetry.
By default, true.

Example from `terraform.tfvars`:

```hcl
telemetry_enabled = true
```

### `dcgm_job_mapping_enabled`

Whether to enable dcgm job mapping (adds hpc_job label on DCGM_ metrics).
By default, true.

Example from `terraform.tfvars`:

```hcl
dcgm_job_mapping_enabled = true
```

### `soperator_notifier`

Configuration of the Soperator Notifier (https://github.com/nebius/soperator/tree/main/helm/soperator-notifier).

Example from `terraform.tfvars`:

```hcl
soperator_notifier = {
  enabled = false
}
```

### `public_o11y_enabled`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
public_o11y_enabled = true
```

## Infrastructure / Slurm / Accounting

### `accounting_enabled`

Whether to enable Accounting.
By default, true.

Example from `terraform.tfvars`:

```hcl
accounting_enabled = true
```

## Infrastructure / Backups

### `backups_enabled`

Whether to enable Backups. Choose from 'auto', 'force_enable', 'force_disable'.
'auto' turns backups on for jails with max size less than 12 TB and is a default option.

Example from `terraform.tfvars`:

```hcl
backups_enabled = "auto"
```

### `backups_password`

Password to be used for encrypting jail backups.

Example from `terraform.tfvars`:

```hcl
backups_password = "password"
```

### `backups_schedule`

Cron schedule for backup task.
See https://docs.k8up.io/k8up/references/schedule-specification.html for more info.

Example from `terraform.tfvars`:

```hcl
backups_schedule = "@daily-random"
```

### `backups_prune_schedule`

Cron schedule for prune task (when old backups are discarded).
See https://docs.k8up.io/k8up/references/schedule-specification.html for more info.

Example from `terraform.tfvars`:

```hcl
backups_prune_schedule = "@daily-random"
```

### `backups_retention`

Backups retention policy - how many last automatic backups to save.
Helps to save storage and to get rid of old backups as they age.
Manually created backups (without autobackup tag) are not discarded.
You can set keepLast, keepHourly, keepDaily, keepWeekly, keepMonthly and keepYearly.

Example from `terraform.tfvars`:

```hcl
backups_retention = {
  # How many daily snapshots to save.
  # ---
  keepDaily = 7
}
```

### `cleanup_bucket_on_destroy`

Whether to delete on destroy all backup data from bucket or not.

Example from `terraform.tfvars`:

```hcl
cleanup_bucket_on_destroy = false
```

## Infrastructure / k8s

### `k8s_version`

Version of the k8s to be used.
Set to null or don't set to use Nebius default (recommended), or specify explicitly

Example from `terraform.tfvars`:

```hcl
k8s_version = 1.32
```

### `nvidia_admin_conf_lines`

Lines to write to /etc/modprobe.d/nvidia_admin.conf via cloud-init (GPU workers only).

Example from `terraform.tfvars`:

```hcl
nvidia_admin_conf_lines = [
  "options nvidia NVreg_RestrictProfilingToAdminUsers=0", # Allow access to GPU counters in nsys profiler for non-root users
  "options nvidia NVreg_EnableStreamMemOPs=1",
  "options nvidia NVreg_RegistryDwords=\"PeerMappingOverride=1;\"",
]
```

## Regeneration

Run this from `website/`:

```bash
npm run generate:soperator-docs
```

