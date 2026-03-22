---
sidebar_position: 4
---

# Configuration Reference

This is not a full variable dump. It is the shortlist of settings that shape cluster behavior the most when you are adapting `soperator/installations/example/terraform.tfvars`.

## Identity and project scope

- `company_name`
  - Used for Slurm and Kubernetes naming and for the kubeconfig context
- `production`
  - Controls whether production-only safeguards apply
- `iam_merge_request_url`
  - Required when `production = true`
- `iam_project_id`, `iam_tenant_id`, `region`, `vpc_subnet_id`
  - Core cloud placement and ownership inputs

## Shared storage

The storage layer is central to the design.

- `filestore_jail`
  - Main shared filesystem mounted across the cluster
- `filestore_jail_submounts`
  - Extra shared filesystems for data-heavy or separated workloads
- `filestore_accounting`
  - Required when accounting is enabled
- `controller_state_on_filestore`
  - Legacy compatibility switch for controller state placement

Practical guidance:

- Use submounts when you need separate data lifecycles inside the jail model.
- Be cautious when attaching pre-existing filesystems directly to active cluster paths.
- Large jails may affect the default backup behavior described in the example tfvars comments.

## Worker capacity and GPU shape

The main tuning surface is `slurm_nodeset_workers`.

For each worker nodeset, pay attention to:

- `size`
- `resource.platform`
- `resource.preset`
- `boot_disk`
- `gpu_cluster.infiniband_fabric`
- `preemptible`
- `autoscaling`
- `reservation_policy`
- `local_nvme`

The installation code converts worker nodesets into Kubernetes node group definitions, including a v2 path for autoscaling and named nodesets.

## Slurm partition behavior

Partition layout is controlled with:

- `slurm_nodesets_partitions`
- `slurm_partition_config_type`
- `slurm_partition_raw_config`

The example configuration keeps a visible `main` partition and a `hidden` partition. The comments in the example tfvars make it clear that users should preserve at least one default partition.

## Login and access

- `slurm_login_public_ip`
  - Controls whether the login load balancer is publicly reachable
- `slurm_login_ssh_root_public_keys`
  - SSH keys for connecting to the Slurm environment
- `k8s_cluster_node_ssh_access_users`
  - Only needed if you want direct SSH-level management of Kubernetes cluster nodes

## Optional infrastructure

- `nfs_in_k8s`
  - NFS service settings when that pattern is enabled
- `node_local_jail_submounts`
  - Per-node extra disks mounted into the jail
- `node_local_image_disk`
  - Separate disk for Docker or Enroot images and container filesystems
- observability and telemetry flags
  - Determine whether Nebius observability integration and related components are enabled

## Recommendation

When documenting this solution further, the next useful step is to add a generated variable appendix or a dedicated config matrix built from the Terraform schema. For now, this page is meant to help operators find the high-impact controls quickly.
