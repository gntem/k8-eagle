locals {
  app_name = "k8-eagle"
  labels = {
    app     = local.app_name
    version = var.image_tag
  }
  
  config_yaml = yamlencode({
    watchers = var.watchers
  })
}
