
resource "kubernetes_namespace_v1" "nims" {

  metadata {
    name = var.namespace
  }
}


resource "kubernetes_secret_v1" "nvcrio-cred" {
  depends_on = [kubernetes_namespace_v1.nims]
  metadata {
    name      = "nvcrio-cred"
    namespace = var.namespace
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "nvcr.io" = {
          username = "$oauthtoken"
          password = var.ngc_key
          auth     = base64encode("$oauthtoken:${var.ngc_key}")
        }
      }
    })
  }
}


resource "kubernetes_secret_v1" "ngc_api_key" {
  depends_on = [kubernetes_namespace_v1.nims]
  metadata {
    name      = "ngc-api-key"
    namespace = var.namespace
  }
  data = {
    NGC_API_KEY = var.ngc_key
  }
  type = "Opaque"
}





resource "kubernetes_service_v1" "openfold3_lb" {
  depends_on = [kubernetes_namespace_v1.nims]
  metadata {
    name      = "nims"
    namespace = var.namespace
  }

  spec {
    selector = {
      lb_group = "protein-apps"
    }


    type = "LoadBalancer"

    port {
      name        = "openfold3"
      port        = 8000
      target_port = 8000
      protocol    = "TCP"
    }

    port {
      name        = "boltz2"
      port        = 8001
      target_port = 8000
      protocol    = "TCP"
    }

    port {
      name        = "evo2-40b"
      port        = 8002
      target_port = 8000
      protocol    = "TCP"
    }
    port {
      name        = "msa-search"
      port        = 8003
      target_port = 8000
      protocol    = "TCP"
    }
    port {
      name        = "openfold2"
      port        = 8004
      target_port = 8000
      protocol    = "TCP"
    }
    port {
      name        = "genmol"
      port        = 8005
      target_port = 8000
      protocol    = "TCP"
    }
  }
}
