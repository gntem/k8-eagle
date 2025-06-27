resource "kubernetes_deployment" "k8_eagle" {
  metadata {
    name      = local.app_name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = local.app_name
      }
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        service_account_name = kubernetes_service_account.k8_eagle.metadata[0].name

        container {
          name              = local.app_name
          image             = "${var.image_name}:${var.image_tag}"
          image_pull_policy = "IfNotPresent"

          env {
            name  = "CONFIG_PATH"
            value = "/config/config.yaml"
          }

          env {
            name  = "SECRETS_PATH"
            value = "/secrets"
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/config"
          }

          volume_mount {
            name       = "secrets-volume"
            mount_path = "/secrets"
          }

          resources {
            requests = {
              memory = var.resources.requests.memory
              cpu    = var.resources.requests.cpu
            }
            limits = {
              memory = var.resources.limits.memory
              cpu    = var.resources.limits.cpu
            }
          }

          liveness_probe {
            exec {
              command = ["/bin/sh", "-c", "pgrep -f k8-eagle"]
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          readiness_probe {
            exec {
              command = ["/bin/sh", "-c", "pgrep -f k8-eagle"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }

        volume {
          name = "config-volume"
          config_map {
            name = kubernetes_config_map.k8_eagle_config.metadata[0].name
          }
        }

        volume {
          name = "secrets-volume"
          secret {
            secret_name = kubernetes_secret.k8_eagle_secret.metadata[0].name
          }
        }

        restart_policy = "Always"
      }
    }
  }

  depends_on = [
    kubernetes_cluster_role_binding.k8_eagle,
    kubernetes_config_map.k8_eagle_config,
    kubernetes_secret.k8_eagle_secret
  ]
}
