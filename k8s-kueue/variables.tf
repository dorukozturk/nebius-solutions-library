# Global
variable "tenant_id" {
  description = "Tenant ID."
  type        = string
}

variable "parent_id" {
  description = "Project ID."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID."
  type        = string
}

variable "region" {
  description = "The current region."
  type        = string
}

# K8s cluster
variable "cluster_name" {
  description = "Base name used for MK8s cluster and related resources (node groups, service accounts)."
  type        = string
  default     = "k8s-kueue"
}

variable "k8s_version" {
  description = "Kubernetes version to be used in the cluster. Leave null to use backend default (recommended), or choose 1.31 or above."
  type        = string
  default     = null
}

variable "etcd_cluster_size" {
  description = "Size of etcd cluster."
  type        = number
  default     = 3
}

variable "mk8s_cluster_public_endpoint" {
  description = "Assign public endpoint to MK8S cluster to make it directly accessible from the external internet."
  type        = bool
  default     = true
}

# K8s access
variable "ssh_user_name" {
  description = "SSH username."
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "SSH Public Key to access the cluster nodes"
  type = object({
    key  = optional(string),
    path = optional(string, "~/.ssh/id_rsa.pub")
  })
  default = {}
  validation {
    condition     = var.ssh_public_key.key != null || fileexists(var.ssh_public_key.path)
    error_message = "SSH Public Key must be set by `key` or file `path` ${var.ssh_public_key.path}"
  }
}

variable "enable_k8s_node_group_sa" {
  description = "Enable K8S Node Group Service Account"
  type        = bool
  default     = true
}

# K8s CPU node group
variable "cpu_nodes_fixed_count" {
  description = "Number of nodes in the CPU-only node group."
  type        = number
  default     = 2
}

variable "cpu_nodes_platform" {
  description = "Platform for nodes in the CPU-only node group."
  type        = string
  default     = null
}

variable "cpu_nodes_preset" {
  description = "CPU and RAM configuration for nodes in the CPU-only node group."
  type        = string
  default     = null
}

variable "cpu_disk_type" {
  description = "Disk type for nodes in the CPU-only node group."
  type        = string
  default     = "NETWORK_SSD"
}

variable "cpu_disk_size" {
  description = "Disk size (in GB) for nodes in the CPU-only node group."
  type        = string
  default     = "128"
}

variable "cpu_nodes_autoscaling" {
  type = object({
    enabled  = optional(bool, false)
    min_size = optional(number)
    max_size = optional(number)
  })
  default = {}
}

variable "cpu_nodes_preemptible" {
  description = "Whether the cpu nodes should be preemptible"
  type        = bool
  default     = false
}

variable "cpu_nodes_public_ips" {
  description = "Assign public IP address to CPU nodes to make them directly accessible from the external internet."
  type        = bool
  default     = false
}

# K8s GPU node group
variable "gpu_nodes_fixed_count" {
  description = "Number of nodes in the GPU node group."
  type        = number
  default     = 1
}

variable "gpu_nodes_autoscaling" {
  type = object({
    enabled  = optional(bool, false)
    min_size = optional(number)
    max_size = optional(number)
  })
  default = {}
}

variable "gpu_nodes_platform" {
  description = "Platform for nodes in the GPU node group."
  type        = string
  default     = null
}

variable "gpu_nodes_preset" {
  description = "Configuration for GPU amount, CPU, and RAM for nodes in the GPU node group."
  type        = string
  default     = null
}

variable "gpu_disk_type" {
  description = "Disk type for nodes in the GPU node group."
  type        = string
  default     = "NETWORK_SSD"
}

variable "gpu_disk_size" {
  description = "Disk size (in GB) for nodes in the GPU node group."
  type        = string
  default     = "512"
}

variable "gpu_nodes_preemptible" {
  description = "Use preemptible VMs for GPU nodes"
  type        = bool
  default     = false
}

variable "gpu_nodes_public_ips" {
  description = "Assign public IP address to GPU nodes to make them directly accessible from the external internet."
  type        = bool
  default     = false
}

# K8s filestore
variable "enable_filestore" {
  description = "Use Filestore."
  type        = bool
  default     = false
}

variable "existing_filestore" {
  description = "Add existing SFS"
  type        = string
  default     = ""
}

variable "filestore_disk_type" {
  description = "Filestore disk type."
  type        = string
  default     = "NETWORK_SSD"
}

variable "filestore_disk_size_gibibytes" {
  description = "Filestore disk size in GiB."
  type        = number
  default     = 100
}

variable "filestore_block_size_kibibytes" {
  description = "Filestore block size in KiB."
  type        = number
  default     = 4
}

variable "filestore_mount_path" {
  description = "Mount path for the shared filesystem on Kubernetes nodes."
  type        = string
  default     = "/mnt/data"
}

variable "filesystem_csi" {
  description = "Configuration for Nebius Shared Filesystem CSI installation when a shared filesystem is present. Set previous_default_storage_class_name to an empty string to skip demoting another StorageClass."
  type = object({
    chart_version                       = optional(string, "0.1.5")
    namespace                           = optional(string, "kube-system")
    make_default_storage_class          = optional(bool, true)
    previous_default_storage_class_name = optional(string, "compute-csi-default-sc")
  })
  default = {}
}

# Kueue
variable "kueue_version" {
  description = "Version of Kueue to install."
  type        = string
  default     = "0.17.1"
}

# Observability
variable "enable_nebius_o11y_agent" {
  description = "Enable Nebius Observability Agent for Kubernetes [marketplace/nebius/nebius-observability-agent]"
  type        = bool
  default     = false
}

variable "collectK8sClusterMetrics" {
  description = "Enable collection of Kubernetes cluster metrics in Nebius Observability Agent"
  type        = bool
  default     = false
}

variable "enable_grafana" {
  description = "Enable Grafana [marketplace/nebius/grafana-solution-by-nebius]"
  type        = bool
  default     = false
}

variable "loki" {
  type = object({
    enabled            = optional(bool, false)
    region             = optional(string)
    replication_factor = optional(number)
  })
  default = {}
}

variable "enable_prometheus" {
  description = "Enable Prometheus for metrics collection."
  type        = bool
  default     = false
}

# Helm
variable "iam_token" {
  description = "Token for Helm provider authentication. (source environment.sh)"
  type        = string
}

variable "test_mode" {
  description = "Switch between real usage and testing"
  type        = bool
  default     = false
}
