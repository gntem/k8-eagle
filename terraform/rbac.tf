resource "kubernetes_service_account" "k8_eagle" {
  metadata {
    name      = local.app_name
    namespace = var.namespace
    labels    = local.labels
  }
}

resource "kubernetes_cluster_role" "k8_eagle" {
  metadata {
    name   = local.app_name
    labels = local.labels
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "k8_eagle" {
  metadata {
    name   = local.app_name
    labels = local.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.k8_eagle.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.k8_eagle.metadata[0].name
    namespace = var.namespace
  }
}
