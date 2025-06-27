resource "kubernetes_config_map" "k8_eagle_config" {
  metadata {
    name      = "${local.app_name}-config"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    "config.yaml" = local.config_yaml
  }
}

resource "kubernetes_secret" "k8_eagle_secret" {
  metadata {
    name      = "${local.app_name}-secret"
    namespace = var.namespace
    labels    = local.labels
  }

  type = "Opaque"

  data = {
    for key, value in var.auth_tokens : key => base64encode(value)
  }
}
