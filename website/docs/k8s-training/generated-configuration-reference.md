---
sidebar_position: 4
---

# Generated Configuration Reference

This page is generated from `k8s-training/terraform.tfvars` and the region defaults defined in `k8s-training/locals.tf`.

Generation date: 2026-03-22

## Region defaults

### `eu-west1`

- CPU: `cpu-d3` / `16vcpu-64gb`
- GPU: `gpu-h200-sxm` / `8gpu-128vcpu-1600gb`
- InfiniBand fabric: `fabric-5`

### `eu-north1`

- CPU: `cpu-d3` / `16vcpu-64gb`
- GPU: `gpu-h100-sxm` / `8gpu-128vcpu-1600gb`
- InfiniBand fabric: `fabric-3`

### `eu-north2`

- CPU: `cpu-d3` / `16vcpu-64gb`
- GPU: `gpu-h200-sxm` / `8gpu-128vcpu-1600gb`
- InfiniBand fabric: `eu-north2-a`

### `us-central1`

- CPU: `cpu-d3` / `16vcpu-64gb`
- GPU: `gpu-h200-sxm` / `8gpu-128vcpu-1600gb`
- InfiniBand fabric: `us-central1-a`

### `me-west1`

- CPU: `cpu-d3` / `16vcpu-64gb`
- GPU: `gpu-b200-sxm-a` / `8gpu-160vcpu-1792gb`
- InfiniBand fabric: `ramon`

### `uk-south1`

- CPU: `cpu-d3` / `16vcpu-64gb`
- GPU: `gpu-b300-sxm` / `8gpu-192vcpu-2768gb`
- InfiniBand fabric: `uk-south1-a`

## tfvars catalog

## General

### `cluster_name`

Mk8s cluster name. By default it is "k8s-training"

Example from `terraform.tfvars`:

```hcl
cluster_name = "k8s-training"
```

## SSH config

### `ssh_user_name`

Username you want to use to connect to the nodes

Example from `terraform.tfvars`:

```hcl
ssh_user_name = "ubuntu" # Username you want to use to connect to the nodes
```

### `ssh_public_key`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
ssh_public_key = {
  key = "put customers public ssh key here"
  # path = "put path to public ssh key here"
}
```

## K8s nodes

### `cpu_nodes_fixed_count`

Used only when cpu_nodes_autoscaling.enabled = false

Example from `terraform.tfvars`:

```hcl
cpu_nodes_fixed_count = 2 # Used only when cpu_nodes_autoscaling.enabled = false
```

### `cpu_nodes_autoscaling`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
cpu_nodes_autoscaling = {
  enabled = false
  # min_size options:
  # - null: min=max, no scale-down (default, recommended - saves ~10 min on initial provisioning)
  #   it can be changed to a number later if needed.
  # - N: can scale down to N nodes
  min_size = null
  max_size = 4
}
```

### `gpu_nodes_fixed_count_per_group`

Number of GPU nodes per group, used only when gpu_nodes_autoscaling.enabled = false

Example from `terraform.tfvars`:

```hcl
gpu_nodes_fixed_count_per_group = 1 # Number of GPU nodes per group, used only when gpu_nodes_autoscaling.enabled = false
```

### `gpu_nodes_autoscaling`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
gpu_nodes_autoscaling = {
  enabled = false
  # min_size options:
  # - null: min=max, no scale-down (default, recommended - saves ~10 min on initial provisioning)
  #   it can be changed to a number later if needed.
  # - N: can scale down to N nodes
  min_size = null
  max_size = 1
}
```

### `gpu_node_groups`

In case you need more then 100 nodes in cluster you have to put multiple node groups

Example from `terraform.tfvars`:

```hcl
gpu_node_groups = 1 # In case you need more then 100 nodes in cluster you have to put multiple node groups
```

### `cpu_nodes_platform`

CPU platform and presets: https://docs.nebius.com/compute/virtual-machines/types#cpu-configurations
CPU nodes platform

Example from `terraform.tfvars`:

```hcl
cpu_nodes_platform = "cpu-d3"     # CPU nodes platform
```

### `cpu_nodes_preset`

CPU nodes preset

Example from `terraform.tfvars`:

```hcl
cpu_nodes_preset   = "4vcpu-16gb" # CPU nodes preset
```

### `gpu_nodes_platform`

GPU platform and preset: https://docs.nebius.com/compute/virtual-machines/types#gpu-configurations
GPU nodes platform: gpu-h100-sxm, gpu-h200-sxm, gpu-b200-sxm

Example from `terraform.tfvars`:

```hcl
gpu_nodes_platform = "gpu-h200-sxm"        # GPU nodes platform: gpu-h100-sxm, gpu-h200-sxm, gpu-b200-sxm
```

### `gpu_nodes_preset`

GPU nodes preset: 8gpu-128vcpu-1600gb, 8gpu-128vcpu-1600gb, 8gpu-160vcpu-1792gb

Example from `terraform.tfvars`:

```hcl
gpu_nodes_preset   = "8gpu-128vcpu-1600gb" # GPU nodes preset: 8gpu-128vcpu-1600gb, 8gpu-128vcpu-1600gb, 8gpu-160vcpu-1792gb
```

### `infiniband_fabric`

Infiniband fabrics: https://docs.nebius.com/compute/clusters/gpu#fabrics
Infiniband fabric name

Example from `terraform.tfvars`:

```hcl
infiniband_fabric = "" # Infiniband fabric name
```

### `gpu_nodes_driverfull_image`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
gpu_nodes_driverfull_image = true
```

### `enable_k8s_node_group_sa`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
enable_k8s_node_group_sa   = true
```

### `enable_egress_gateway`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
enable_egress_gateway      = false
```

### `cpu_nodes_preemptible`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
cpu_nodes_preemptible      = false
```

### `gpu_nodes_preemptible`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
gpu_nodes_preemptible      = false
```

### `cpu_nodes_public_ips`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
cpu_nodes_public_ips         = false
```

### `gpu_nodes_public_ips`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
gpu_nodes_public_ips         = false
```

### `mk8s_cluster_public_endpoint`

Set it to FALSE only in case if you've deployed the [bastion](https://github.com/nebius/nebius-solutions-library/blob/main/bastion/README.md)

Example from `terraform.tfvars`:

```hcl
mk8s_cluster_public_endpoint = true # Set it to FALSE only in case if you've deployed the [bastion](https://github.com/nebius/nebius-solutions-library/blob/main/bastion/README.md)
```

## Observability by Nebius

### `enable_nebius_o11y_agent`

Enable or disable Nebius Observability Agent deployment with true or false

Example from `terraform.tfvars`:

```hcl
enable_nebius_o11y_agent = true # Enable or disable Nebius Observability Agent deployment with true or false
```

### `enable_grafana`

Enable or disable Grafana® solution by Nebius with true or false

Example from `terraform.tfvars`:

```hcl
enable_grafana           = true # Enable or disable Grafana® solution by Nebius with true or false
```

## Local Observability installation

### `enable_prometheus`

Enable or disable Prometheus and Grafana deployment with true or false

Example from `terraform.tfvars`:

```hcl
enable_prometheus = false # Enable or disable Prometheus and Grafana deployment with true or false
```

### `loki`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
loki = {
  enabled            = true # Enable or disable Loki deployment with true or false
  replication_factor = 2    # Number of Loki replicas for each log chunk (higher = better availability, more storage/network cost)
}
```

## Storage

### `enable_filestore`

Enable or disable Filestore integration with true or false

Example from `terraform.tfvars`:

```hcl
enable_filestore               = false # Enable or disable Filestore integration with true or false
```

### `existing_filestore`

If enable_filestore = true, with this variable we can add existing filestore. Require string, example existing_filestore = "computefilesystem-e00r7z9vfxmg1bk99s"

Example from `terraform.tfvars`:

```hcl
existing_filestore             = ""    # If enable_filestore = true, with this variable we can add existing filestore. Require string, example existing_filestore = "computefilesystem-e00r7z9vfxmg1bk99s"
```

### `filestore_disk_size_gibibytes`

Set Filestore disk size in Gbytes.

Example from `terraform.tfvars`:

```hcl
filestore_disk_size_gibibytes  = 100   # Set Filestore disk size in Gbytes.
```

### `filestore_block_size_kibibytes`

Set Filestore block size in bytes

Example from `terraform.tfvars`:

```hcl
filestore_block_size_kibibytes = 4     # Set Filestore block size in bytes
```

## KubeRay Cluster

### `enable_kuberay_cluster`

for GPU isolation to work with kuberay, gpu_nodes_driverfull_image must be set
to false.  This is because we enable acess to infiniband via securityContext.privileged
Turn KubeRay to false, otherwise gpu capacity will be consumed by KubeRay cluster

Example from `terraform.tfvars`:

```hcl
enable_kuberay_cluster = false # Turn KubeRay to false, otherwise gpu capacity will be consumed by KubeRay cluster
```

## kuberay CPU worker setup

### `kuberay_min_cpu_replicas`

if you have no CPU only nodes, set these to zero

Example from `terraform.tfvars`:

```hcl
kuberay_min_cpu_replicas = 1
```

### `kuberay_max_cpu_replicas`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
kuberay_max_cpu_replicas = 2
```

## kuberay GPU worker pod setup

### `kuberay_min_gpu_replicas`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
kuberay_min_gpu_replicas = 2
```

### `kuberay_max_gpu_replicas`

_No inline description in `terraform.tfvars`._

Example from `terraform.tfvars`:

```hcl
kuberay_max_gpu_replicas = 8
```

## KubeRay Service

### `enable_kuberay_service`

Enable to deploy KubeRay Operator with RayService CR

Example from `terraform.tfvars`:

```hcl
enable_kuberay_service = false
```

## Regeneration

Run this from `website/`:

```bash
npm run generate:k8s-training-docs
```

