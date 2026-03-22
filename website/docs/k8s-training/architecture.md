---
sidebar_position: 2
---

# K8s Training Architecture

The `k8s-training` recipe is simpler than `soperator`: it provisions a managed Kubernetes cluster directly and layers operators and optional workload components on top.

## Simplified flow

```text
Terraform recipe
  -> Nebius managed Kubernetes control plane
  -> CPU and GPU node groups
  -> optional Filestore attachment
  -> network, GPU, and observability operators
  -> optional Ray and test components
```

## Cluster layer

The core cluster is created in `k8s-training/main.tf`.

It defines:

- a managed control plane
- configurable public or private endpoint exposure
- CPU node groups
- one or more GPU node groups
- autoscaling or fixed-size node group behavior

## CPU and GPU node pools

The recipe separates general-purpose and accelerated workloads:

- CPU node group
  - baseline cluster services and CPU-only workloads
- GPU node groups
  - training workloads
  - optional GPU cluster / InfiniBand integration
  - optional MIG configuration labels

Region-specific defaults for platform, preset, and InfiniBand fabric are defined in `k8s-training/locals.tf`.

## Storage layer

If Filestore is enabled, the recipe either:

- creates a new shared filesystem, or
- attaches an existing one

That filesystem is then exposed to node groups using a mounted filesystem configuration and can be used for shared storage patterns inside the cluster.

## Add-on layer

The recipe can install:

- Network Operator
- GPU Operator, custom GPU Operator, or device plugin depending on driver mode
- Nebius observability agent
- Grafana
- Prometheus
- Loki
- Cilium egress gateway

## Optional workload layer

`applications.tf` adds optional KubeRay components:

- `RayCluster`
- `RayService`

This makes the recipe useful not only for raw Kubernetes training jobs but also for Ray-based distributed workloads.
