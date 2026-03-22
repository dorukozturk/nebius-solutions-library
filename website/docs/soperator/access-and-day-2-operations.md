---
sidebar_position: 5
---

# Access and Day-2 Operations

Once `terraform apply` completes, there are two different things to validate: Kubernetes control-plane access and Slurm login access.

## Kubernetes access

The `k8s` module runs `nebius mk8s cluster get-credentials` during provisioning and writes a kubeconfig context locally.

Check contexts:

```bash
kubectl config get-contexts
```

Switch to the new context if needed:

```bash
kubectl config use-context nebius-<your-company-name>-slurm
```

Verify cluster health:

```bash
kubectl get pods --all-namespaces
```

The repo README suggests confirming that pods are not stuck in error states and that cluster resources appear healthy in the Nebius console.

## Slurm login access

You can obtain the login address from Terraform state:

```bash
export SLURM_IP=$(terraform state show module.login_script.terraform_data.lb_service_ip | grep 'input' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
ssh root@$SLURM_IP -i ~/.ssh/<private_key>
```

Or use the generated helper:

```bash
./login.sh -k ~/.ssh/<private_key>
```

## Kubernetes endpoint view from the console

The repo includes a screenshot for the Kubernetes connection flow:

![Connect to Kubernetes](/img/soperator/connect_k8s.png)

## Storage operations

The most important day-2 storage question is whether the jail and any data submounts match the workload lifecycle you want:

- persistent shared user environment
- benchmark dataset storage
- ephemeral local worker scratch space
- image or container filesystem caching

This is why the example configuration separates:

- shared filestore-backed mounts
- optional node-local mounts
- optional dedicated image disks

## Destroy path awareness

The installation includes cleanup modules and scripts. Before tearing down a cluster, verify which storage objects were created by Terraform versus attached as pre-existing resources so you do not destroy data unintentionally.
