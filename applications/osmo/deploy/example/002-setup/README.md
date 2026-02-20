# Kubernetes Setup Scripts

This directory contains scripts for configuring the Kubernetes cluster with GPU infrastructure and OSMO components.

## Prerequisites

1. Complete infrastructure deployment (001-iac)
2. kubectl configured with cluster access:
   ```bash
   nebius mk8s cluster get-credentials --id <cluster-id> --external
   ```

## Deployment Order

Run scripts in order:

```bash
# 1. GPU Infrastructure (GPU Operator, Network Operator, KAI Scheduler)
./01-deploy-gpu-infrastructure.sh

# 2. Observability (Prometheus, Grafana, Loki)
./02-deploy-observability.sh

# 3. NGINX Ingress Controller (required – provides routing for OSMO services)
./03-deploy-nginx-ingress.sh

# 4. OSMO Control Plane
./04-deploy-osmo-control-plane.sh

# 5. OSMO Backend
./05-deploy-osmo-backend.sh

# 6. Configure Storage (requires port-forward, see main README)
./06-configure-storage.sh

# 7. Configure GPU Platform (required for GPU workflows)
./08-configure-gpu-platform.sh
```

## Scripts

| Script | Purpose | Duration |
|--------|---------|----------|
| `01-deploy-gpu-infrastructure.sh` | GPU Operator, Network Operator, KAI Scheduler | ~15 min |
| `02-deploy-observability.sh` | Prometheus, Grafana, Loki, Promtail | ~10 min |
| `03-deploy-nginx-ingress.sh` | NGINX Ingress Controller (routing for OSMO services) | ~2 min |
| `04-deploy-osmo-control-plane.sh` | OSMO Control Plane, Ingress resources, database secrets, service URL | ~5 min |
| `05-deploy-osmo-backend.sh` | OSMO Backend operator | ~5 min |
| `06-configure-storage.sh` | Configure S3-compatible storage for workflow logs/data | ~1 min |
| `07-configure-service-url.sh` | Reconfigure service URL manually (usually not needed) | ~1 min |
| `08-configure-gpu-platform.sh` | Configure GPU platform with tolerations/node selector | ~1 min |

## Configuration

### Helm Values

Customize deployments by editing files in `values/`:

| File | Component |
|------|-----------|
| `gpu-operator.yaml` | NVIDIA GPU Operator |
| `network-operator.yaml` | NVIDIA Network Operator |
| `kai-scheduler.yaml` | KAI GPU Scheduler |
| `prometheus.yaml` | Prometheus + Grafana |
| `loki.yaml` | Loki Log Aggregation |
| `promtail.yaml` | Log Collection |

### Environment Variables

Configure via `defaults.sh` or export before running:

```bash
# Namespaces
GPU_OPERATOR_NAMESPACE="gpu-operator"
NETWORK_OPERATOR_NAMESPACE="network-operator"
MONITORING_NAMESPACE="monitoring"
OSMO_NAMESPACE="osmo"

# Grafana password (auto-generated if empty)
GRAFANA_ADMIN_PASSWORD=""

# NGINX Ingress (deploy 03-deploy-nginx-ingress.sh before 04-deploy-osmo-control-plane.sh)
OSMO_INGRESS_HOSTNAME=""         # hostname for Ingress rules (e.g. osmo.example.com); leave empty for IP-based access
OSMO_INGRESS_BASE_URL=""         # override for service_base_url; auto-detected from LoadBalancer if empty
```

### Secrets from MysteryBox

If you ran `secrets-init.sh` in the prerequisites step, the following environment variables are set:

| Variable | Description |
|----------|-------------|
| `TF_VAR_postgresql_mysterybox_secret_id` | MysteryBox secret ID for PostgreSQL password |
| `TF_VAR_mek_mysterybox_secret_id` | MysteryBox secret ID for MEK (Master Encryption Key) |

The `04-deploy-osmo-control-plane.sh` script automatically reads these secrets from MysteryBox. This keeps sensitive credentials out of Terraform state and provides a secure secrets management workflow.

**Secret retrieval order:**
1. **MysteryBox** (if secret ID is set via `TF_VAR_*` or `OSMO_*` env vars)
2. **Terraform outputs** (fallback)
3. **Environment variables** (fallback)
4. **Interactive prompt** (last resort)

To manually retrieve secrets from MysteryBox:
```bash
# PostgreSQL password
nebius mysterybox v1 payload get-by-key \
  --secret-id $TF_VAR_postgresql_mysterybox_secret_id \
  --key password --format json | jq -r '.data.string_value'

# MEK (Master Encryption Key)
nebius mysterybox v1 payload get-by-key \
  --secret-id $TF_VAR_mek_mysterybox_secret_id \
  --key mek --format json | jq -r '.data.string_value'
```

## Accessing Services

### Grafana Dashboard

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000
# User: admin
# Password: (shown during deployment or in defaults.sh)
```

### Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090
```

### OSMO API

```bash
kubectl port-forward -n osmo svc/osmo-service 8080:80
# Open http://localhost:8080
```

### OSMO Web UI

```bash
kubectl port-forward -n osmo svc/osmo-ui 8081:80
# Open http://localhost:8081
```

## Cleanup

Run cleanup scripts in reverse order:

```bash
cd cleanup

# Remove OSMO
./uninstall-osmo-backend.sh
./uninstall-osmo-control-plane.sh

# Remove observability
./uninstall-observability.sh

# Remove GPU infrastructure
./uninstall-gpu-infrastructure.sh
```

## Configure OSMO GPU Platform

After deploying OSMO backend, configure the GPU platform so OSMO can schedule workloads on GPU nodes.

### Why is this needed?

Nebius GPU nodes have a taint `nvidia.com/gpu=true:NoSchedule` that prevents pods from being scheduled unless they have matching tolerations. OSMO needs to be configured with:

1. A **pod template** with GPU tolerations and node selector
2. A **GPU platform** that references this pod template

### Option 1: Run the Configuration Script (Recommended)

```bash
./08-configure-gpu-platform.sh
```

### Option 2: Manual Configuration via API

With port-forward running (`kubectl port-forward -n osmo svc/osmo-service 8080:80`):

**Step 1: Create GPU Pod Template**

```bash
curl -X PUT 'http://localhost:8080/api/configs/pod_template/gpu_tolerations' \
  -H 'Content-Type: application/json' \
  -d @gpu_pod_template.json
```

Where `gpu_pod_template.json` contains:

```json
{
  "configs": {
    "spec": {
      "tolerations": [
        {
          "key": "nvidia.com/gpu",
          "operator": "Exists",
          "effect": "NoSchedule"
        }
      ],
      "nodeSelector": {
        "nvidia.com/gpu.present": "true"
      }
    }
  }
}
```

**Step 2: Create GPU Platform**

```bash
curl -X PUT 'http://localhost:8080/api/configs/pool/default/platform/gpu' \
  -H 'Content-Type: application/json' \
  -d @gpu_platform_update.json
```

Where `gpu_platform_update.json` contains:

```json
{
  "configs": {
    "description": "GPU platform for L40S nodes",
    "host_network_allowed": false,
    "privileged_allowed": false,
    "allowed_mounts": [],
    "default_mounts": [],
    "default_variables": {
      "USER_GPU": 1
    },
    "resource_validations": [],
    "override_pod_template": ["gpu_tolerations"]
  }
}
```

### Verify Configuration

```bash
# Check pod templates
curl -s http://localhost:8080/api/configs/pod_template | jq 'keys'
# Should include: "gpu_tolerations"

# Check GPU platform
curl -s http://localhost:8080/api/configs/pool/default | jq '.platforms.gpu'

# Check resources (GPU nodes should now be visible)
curl -s http://localhost:8080/api/resources | jq '.resources[] | {name: .name, gpu: .allocatable_fields.gpu}'
```

### Using GPU in Workflows

Specify `platform: gpu` in your OSMO workflow:

```yaml
workflow:
  name: my-gpu-job
  resources:
    gpu-resource:
      platform: gpu    # <-- Selects GPU platform with tolerations
      gpu: 1
      memory: 4Gi
  tasks:
  - name: train
    image: nvcr.io/nvidia/cuda:12.6.3-base-ubuntu24.04
    command: ["nvidia-smi"]
    resource: gpu-resource
```

## Troubleshooting

### GPU Nodes Not Ready

1. Check GPU operator pods:
   ```bash
   kubectl get pods -n gpu-operator
   ```

2. Check node labels:
   ```bash
   kubectl get nodes -l node-type=gpu --show-labels
   ```

3. Check DCGM exporter:
   ```bash
   kubectl logs -n gpu-operator -l app=nvidia-dcgm-exporter
   ```

### Pods Pending on GPU Nodes

1. Verify tolerations:
   ```bash
   kubectl describe pod <pod-name> | grep -A5 Tolerations
   ```

2. Check node taints:
   ```bash
   kubectl describe node <gpu-node> | grep Taints
   ```

### InfiniBand Issues

1. Check Network Operator:
   ```bash
   kubectl get pods -n network-operator
   ```

2. Verify RDMA devices:
   ```bash
   kubectl exec -n gpu-operator <dcgm-pod> -- ibstat
   ```

### Database Connection Failed

1. Verify PostgreSQL is accessible:
   ```bash
   kubectl get secret osmo-database -n osmo -o yaml
   ```

2. Test connection from a pod:
   ```bash
   kubectl run pg-test --rm -it --image=postgres:16 -- psql -h <host> -U <user> -d <db>
   ```

### OSMO Not Seeing GPU Resources

If OSMO shows 0 GPUs or GPU workflows fail to schedule:

1. Check if GPU platform is configured:
   ```bash
   curl -s http://localhost:8080/api/configs/pool/default | jq '.platforms | keys'
   # Should include "gpu"
   ```

2. Check if GPU pod template exists:
   ```bash
   curl -s http://localhost:8080/api/configs/pod_template | jq 'keys'
   # Should include "gpu_tolerations"
   ```

3. Check GPU node labels and taints:
   ```bash
   kubectl describe node <gpu-node> | grep -E 'Taints:|nvidia.com/gpu'
   # Should show taint: nvidia.com/gpu=true:NoSchedule
   # Should show label: nvidia.com/gpu.present=true
   ```

4. If missing, run the GPU configuration:
   ```bash
   ./08-configure-gpu-platform.sh
   ```

5. Verify OSMO sees GPU resources:
   ```bash
   curl -s http://localhost:8080/api/resources | jq '.resources[] | select(.allocatable_fields.gpu != null)'
   ```
