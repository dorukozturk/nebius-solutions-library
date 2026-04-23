module "network-operator" {
  depends_on = [
    nebius_mk8s_v1_node_group.cpu-only,
    nebius_mk8s_v1_node_group.gpu,
  ]
  source     = "../modules/network-operator"
  parent_id  = var.parent_id
  cluster_id = nebius_mk8s_v1_cluster.k8s-cluster.id
}

module "gpu-operator" {
  depends_on = [
    module.network-operator
  ]
  source       = "../modules/gpu-operator"
  parent_id    = var.parent_id
  cluster_id   = nebius_mk8s_v1_cluster.k8s-cluster.id
  mig_strategy = null
}

module "o11y" {
  source                    = "../modules/o11y"
  parent_id                 = var.parent_id
  tenant_id                 = var.tenant_id
  cluster_id                = nebius_mk8s_v1_cluster.k8s-cluster.id
  k8s_node_group_sa_id      = var.enable_k8s_node_group_sa ? nebius_iam_v1_service_account.k8s_node_group_sa[0].id : null
  k8s_node_group_sa_enabled = var.enable_k8s_node_group_sa

  o11y = {
    nebius_o11y_agent = {
      enabled                  = var.enable_nebius_o11y_agent
      collectK8sClusterMetrics = var.collectK8sClusterMetrics
    }
    grafana = {
      enabled = var.enable_grafana
    }
    loki = {
      enabled            = var.loki.enabled
      replication_factor = var.loki.replication_factor
      region             = var.region
    }
    prometheus = {
      enabled = var.enable_prometheus
      pv_size = "25Gi"
    }
  }
  test_mode = var.test_mode
}

resource "helm_release" "kueue" {
  name             = "kueue"
  chart            = "oci://registry.k8s.io/kueue/charts/kueue"
  version          = var.kueue_version
  namespace        = "kueue-system"
  create_namespace = true
  atomic           = true
  wait             = true

  depends_on = [
    module.network-operator,
    nebius_mk8s_v1_node_group.cpu-only,
    nebius_mk8s_v1_node_group.gpu,
  ]
}
