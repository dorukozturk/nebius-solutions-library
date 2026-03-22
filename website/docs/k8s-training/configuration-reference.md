---
sidebar_position: 3
---

# K8s Training Configuration Reference

This page focuses on the highest-impact variables in `k8s-training/variables.tf` and the defaults defined in `k8s-training/locals.tf`.

## Region defaults

The recipe already maps regions to sensible defaults for:

- CPU platform and preset
- GPU platform and preset
- InfiniBand fabric

Examples from `locals.tf`:

- `eu-north1`
  - CPU: `cpu-d3` / `16vcpu-64gb`
  - GPU: `gpu-h100-sxm` / `8gpu-128vcpu-1600gb`
- `eu-west1`
  - CPU: `cpu-d3` / `16vcpu-64gb`
  - GPU: `gpu-h200-sxm` / `8gpu-128vcpu-1600gb`
- `me-west1`
  - GPU: `gpu-b200-sxm-a` / `8gpu-160vcpu-1792gb`
- `uk-south1`
  - GPU: `gpu-b300-sxm` / `8gpu-192vcpu-2768gb`

You can override those defaults explicitly with:

- `cpu_nodes_platform`
- `cpu_nodes_preset`
- `gpu_nodes_platform`
- `gpu_nodes_preset`
- `infiniband_fabric`

## Core cluster settings

Review these first:

- `cluster_name`
- `k8s_version`
- `etcd_cluster_size`
- `mk8s_cluster_public_endpoint`
- `subnet_id`
- `region`

## CPU node group settings

- `cpu_nodes_fixed_count`
- `cpu_nodes_autoscaling`
- `cpu_nodes_platform`
- `cpu_nodes_preset`
- `cpu_disk_type`
- `cpu_disk_size`
- `cpu_nodes_public_ips`
- `cpu_nodes_preemptible`

## GPU node group settings

- `gpu_node_groups`
- `gpu_nodes_fixed_count_per_group`
- `gpu_nodes_autoscaling`
- `gpu_nodes_platform`
- `gpu_nodes_preset`
- `gpu_disk_type`
- `gpu_disk_size`
- `enable_gpu_cluster`
- `infiniband_fabric`
- `gpu_nodes_public_ips`
- `gpu_nodes_preemptible`

## Driver and MIG behavior

The GPU path has three main modes:

- standard GPU Operator
- custom GPU Operator
- driverfull image plus device plugin

Relevant variables:

- `gpu_nodes_driverfull_image`
- `custom_driver`
- `mig_strategy`
- `mig_parted_config`

The validation in `variables.tf` explicitly prevents enabling both `custom_driver` and `gpu_nodes_driverfull_image` at the same time.

## Storage settings

- `enable_filestore`
- `existing_filestore`
- `filestore_disk_type`
- `filestore_disk_size_gibibytes`
- `filestore_block_size_kibibytes`

Use Filestore when you need shared storage across node groups. The recipe exposes it with a mount tag and the README documents the resulting mounted path as `/mnt/filestore`.

## Observability and platform add-ons

- `enable_nebius_o11y_agent`
- `collectK8sClusterMetrics`
- `enable_grafana`
- `enable_prometheus`
- `loki`
- `enable_egress_gateway`

## Optional workload features

- `enable_kuberay_cluster`
- `enable_kuberay_service`
- `kuberay_*`
- `test_mode`

`test_mode` can also enable NCCL test resources through the `nccl-test` module.
