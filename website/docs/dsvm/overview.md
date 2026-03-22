---
sidebar_position: 1
---

# DSVM Overview

The `dsvm` solution provisions a Data Science Virtual Machine with preinstalled tooling for analytics, experimentation, and model development.

## What it includes

The README lists a prebuilt environment that includes:

- Conda and Python environments
- Jupyter Notebook and JupyterLab
- common data science libraries
- major ML frameworks
- Docker and Git
- NVIDIA drivers and CUDA tooling

## Main use case

Use this when you want a ready-to-use single-machine environment for exploration, notebooks, and model development rather than a multi-node cluster.

## Configuration

The deployment inputs from `dsvm/terraform.tfvars` are documented here:

- [Generated configuration reference](./generated-configuration-reference.md)
