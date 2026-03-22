---
sidebar_position: 6
---

# Testing and Validation

The repository already ships a simple validation path under `soperator/test`.

## What is included

The current test README describes:

- delivery helpers for test assets
- quick checks
- benchmark-related setup guidance

## Upload test assets

Use `deliver.sh` to push the selected test bundle to the cluster:

```bash
./deliver.sh -t quickcheck -u <ssh-user> -k <private-key> -a <login-address>
```

Uploaded content lands under:

```text
/opt/slurm-test
```

## Quick checks

The quick-check path is the fastest post-install validation step and is the right place to start after first provisioning.

From the repo tree, the current quick checks include scripts for:

- container validation
- hello-world style checks
- NCCL single-node checks
- NCCL multi-node checks

## Benchmarks

Benchmark execution is a separate path from smoke testing.

The test README notes that benchmarks require:

- datasets and checkpoints copied to the cluster
- benchmark-specific configuration
- storage that can handle shared access from multiple workers

For that reason, the repo suggests using jail submounts such as `/data` for benchmark datasets.

## Recommended validation flow

1. Confirm Kubernetes health with `kubectl get pods -A`
2. Confirm SSH access through the login endpoint
3. Upload quick-check assets with `deliver.sh`
4. Run NCCL-oriented checks that match the cluster shape you deployed
5. Only then move on to heavier workload benchmarks
