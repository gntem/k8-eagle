variable "namespace" {
  description = "Kubernetes namespace for K8-Eagle deployment"
  type        = string
  default     = "default"
}

variable "image_name" {
  description = "Docker image name for K8-Eagle"
  type        = string
  default     = "k8-eagle"
}

variable "image_tag" {
  description = "Docker image tag for K8-Eagle"
  type        = string
  default     = "latest"
}

variable "replicas" {
  description = "Number of K8-Eagle replicas"
  type        = number
  default     = 1
}

variable "resources" {
  description = "Resource limits and requests for K8-Eagle"
  type = object({
    requests = object({
      memory = string
      cpu    = string
    })
    limits = object({
      memory = string
      cpu    = string
    })
  })
  default = {
    requests = {
      memory = "128Mi"
      cpu    = "250m"
    }
    limits = {
      memory = "256Mi"
      cpu    = "500m"
    }
  }
}

variable "watchers" {
  description = "List of deployment watchers configuration"
  type = list(object({
    name            = string
    deployment_name = string
    namespace       = string
    webhooks = list(object({
      url             = string
      auth_token_key  = string
    }))
  }))
  default = [
    {
      name            = "frontend-watcher"
      deployment_name = "frontend-app"
      namespace       = "production"
      webhooks = [
        {
          url            = "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"
          auth_token_key = "slack-token"
        },
        {
          url            = "https://webhook.site/unique-id-1"
          auth_token_key = "webhook-token"
        }
      ]
    },
    {
      name            = "backend-watcher"
      deployment_name = "backend-api"
      namespace       = "production"
      webhooks = [
        {
          url            = "https://discord.com/api/webhooks/123456789/abcdefghijklmnop"
          auth_token_key = "discord-token"
        }
      ]
    },
    {
      name            = "database-watcher"
      deployment_name = "postgres"
      namespace       = "database"
      webhooks = [
        {
          url            = "https://api.pagerduty.com/integration/v1/webhooks"
          auth_token_key = "pagerduty-token"
        },
        {
          url            = "https://monitoring.example.com/k8s-events"
          auth_token_key = "monitoring-token"
        }
      ]
    }
  ]
}

variable "auth_tokens" {
  description = "Authentication tokens for webhooks (will be base64 encoded)"
  type        = map(string)
  sensitive   = true
  default = {
    slack-token      = "your-slack-token"
    webhook-token    = "your-webhook-token"
    discord-token    = "your-discord-token"
    pagerduty-token  = "your-pagerduty-token"
    monitoring-token = "your-monitoring-token"
  }
}
