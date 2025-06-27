output "deployment_name" {
  description = "Name of the K8-Eagle deployment"
  value       = kubernetes_deployment.k8_eagle.metadata[0].name
}

output "namespace" {
  description = "Namespace where K8-Eagle is deployed"
  value       = var.namespace
}

output "service_account" {
  description = "Service account used by K8-Eagle"
  value       = kubernetes_service_account.k8_eagle.metadata[0].name
}

output "config_map_name" {
  description = "Name of the configuration ConfigMap"
  value       = kubernetes_config_map.k8_eagle_config.metadata[0].name
}

output "secret_name" {
  description = "Name of the secrets Secret"
  value       = kubernetes_secret.k8_eagle_secret.metadata[0].name
}

output "watchers_count" {
  description = "Number of configured watchers"
  value       = length(var.watchers)
}

output "image" {
  description = "Docker image being used"
  value       = "${var.image_name}:${var.image_tag}"
}
