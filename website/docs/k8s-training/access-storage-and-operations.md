---
sidebar_position: 5
---

# Access, Storage, and Operations

After deployment, the first tasks are Kubernetes access, storage verification, and optional observability or workload validation.

## Add cluster credentials to kubeconfig

From the deployment directory:

```bash
nebius mk8s v1 cluster get-credentials --id $(cat terraform.tfstate | jq -r '.resources[] | select(.type == "nebius_mk8s_v1_cluster") | .instances[].attributes.id') --external
```

Then verify:

```bash
kubectl cluster-info
kubectl get pods -A
```

## Outputs worth checking

The recipe exposes:

- `kube_cluster`
- `kube_cluster_ca_certificate`
- `grafana_password`
- `grafana_service_account`
- `shared-filesystem`

These are defined in `k8s-training/output.tf`.

## Observability access

The existing README documents the Grafana access path through the Nebius web console:

`Main menu > Applications > grafana-solution-by-nebius > Endpoints + Create`

The password comes from:

```bash
terraform output grafana_password
```

## Shared storage usage

If Filestore is enabled, the recipe attaches a shared filesystem and the README documents `/mnt/filestore` as the expected host path.

To expose that storage to workloads, the current README suggests creating PV and PVC objects using the mounted storage class.

## Storage caveats from the current README

- the filesystem must be mounted on all relevant node groups
- a PV can consume the shared filesystem capacity
- filesystem size is not auto-updated through the PV spec
- block volume mode is not supported in this pattern

## Optional Ray and test paths

If you enabled:

- `enable_kuberay_cluster`
- `enable_kuberay_service`
- `test_mode`

then your day-2 checks should also include:

- verifying Ray resources are scheduled onto the expected CPU or GPU nodes
- verifying GPU operator or device plugin state
- running NCCL-oriented validation when test mode is enabled
