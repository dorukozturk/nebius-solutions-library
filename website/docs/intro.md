---
sidebar_position: 1
---

# Nebius Solutions Library

This site is the documentation layer for the Terraform and Helm solutions in the Nebius Solutions Library repository.

The initial version focuses on two goals:

- Turn long solution READMEs into a navigable documentation set.
- Create an information architecture that can grow from `soperator` into `k8s-training` and the rest of the library.

## Current scope

The first documented solution is `soperator`, the repository's workflow for running Slurm on Kubernetes on Nebius AI Cloud.

That section covers:

- What the solution deploys
- How the Terraform recipe is structured
- How to install and configure a cluster
- How to access it after provisioning
- How to run validation and quick checks

## Source of truth

The documentation is derived from content and implementation in this repository, primarily:

- `soperator/README.md`
- `soperator/installations/example`
- `soperator/modules/*`
- `soperator/test/*`

As the docs expand, the goal is to keep them close to the code and example configurations instead of maintaining disconnected prose.
