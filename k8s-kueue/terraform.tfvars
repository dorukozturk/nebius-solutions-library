# Mk8s cluster name
cluster_name = "k8s-kueue"

# SSH config
ssh_user_name = "ubuntu"
ssh_public_key = {
  key = "put customers public ssh key here"
  # path = "put path to public ssh key here"
}

# CPU nodes (used for system workloads and Kueue controller)
cpu_nodes_fixed_count = 2
cpu_nodes_autoscaling = {
  enabled  = false
  min_size = null
  max_size = 2
}
cpu_nodes_platform = "cpu-d3"
cpu_nodes_preset   = "4vcpu-16gb"

# GPU nodes - 1 GPU per node (H200 SXM, 200GB system RAM)
# Platform and preset: https://docs.nebius.com/compute/virtual-machines/types#gpu-configurations
gpu_nodes_fixed_count = 1
gpu_nodes_autoscaling = {
  enabled  = false
  min_size = null
  max_size = 1
}
gpu_nodes_platform = "gpu-h200-sxm"
gpu_nodes_preset   = "1gpu-16vcpu-200gb"

enable_k8s_node_group_sa     = true
mk8s_cluster_public_endpoint = true
cpu_nodes_preemptible        = false
gpu_nodes_preemptible        = false
cpu_nodes_public_ips         = false
gpu_nodes_public_ips         = false

# Storage
enable_filestore               = true  # Set to false to skip filestore
existing_filestore             = ""    # Set to an existing filesystem ID to reuse it, e.g. "computefilesystem-e00r7z9vfxmg1bk99s"
filestore_disk_size_gibibytes  = 100
filestore_block_size_kibibytes = 4

# Kueue version
kueue_version = "0.17.1"

# Observability (disabled by default; enable as needed)
enable_nebius_o11y_agent = false
enable_grafana           = false
enable_prometheus        = false
loki = {
  enabled = false
}
