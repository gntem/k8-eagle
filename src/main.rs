use anyhow::Result;
use clap::Parser;
use futures::StreamExt;
use k8s_openapi::api::apps::v1::Deployment;
use kube::{
    api::{Api, WatchEvent, WatchParams},
    Client,
};
use reqwest;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use tokio::task::JoinSet;
use tracing::{error, info, warn};

#[derive(Parser)]
#[command(name = "k8-eagle")]
#[command(about = "Kubernetes deployment watcher with multiple webhook support")]
struct Args {
    #[arg(long, env = "CONFIG_PATH", default_value = "/config/config.yaml")]
    config_path: String,
    
    #[arg(long, env = "SECRETS_PATH", default_value = "/secrets")]
    secrets_path: String,
}

#[derive(Debug, Deserialize, Serialize)]
struct Config {
    watchers: Vec<WatcherConfig>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
struct WatcherConfig {
    name: String,
    deployment_name: String,
    namespace: String,
    webhooks: Vec<WebhookConfig>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
struct WebhookConfig {
    url: String,
    auth_token_key: String,
}

#[derive(Debug, Clone)]
struct ResolvedWebhook {
    url: String,
    auth_token: String,
}

#[derive(Debug, Clone)]
struct ResolvedWatcher {
    name: String,
    deployment_name: String,
    namespace: String,
    webhooks: Vec<ResolvedWebhook>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .json()
        .with_current_span(false)
        .with_span_list(false)
        .init();
    
    let args = Args::parse();
    
    info!(
        config_path = %args.config_path,
        "starting k8-eagle"
    );
    
    let config = load_config(&args.config_path)?;
    info!(
        watchers_count = config.watchers.len(),
        "loaded configuration"
    );
    
    let secrets = load_secrets(&args.secrets_path)?;
    info!(
        secrets_count = secrets.len(),
        "loaded secrets"
    );
    
    let watchers = resolve_watchers(&config, &secrets)?;
    
    let client = Client::try_default().await?;
    
    let mut join_set = JoinSet::new();
    
    for watcher in watchers {
        let client = client.clone();
        join_set.spawn(async move {
            if let Err(e) = watch_deployment(client, watcher).await {
                error!(error = %e, "watcher failed");
            }
        });
    }
    
    while let Some(result) = join_set.join_next().await {
        if let Err(e) = result {
            error!(error = %e, "watcher task failed");
        }
    }
    
    Ok(())
}

fn load_config(config_path: &str) -> Result<Config> {
    let config_content = fs::read_to_string(config_path)?;
    let config: Config = serde_yaml::from_str(&config_content)?;
    Ok(config)
}

fn load_secrets(secrets_path: &str) -> Result<HashMap<String, String>> {
    let mut secrets = HashMap::new();
    
    if !Path::new(secrets_path).exists() {
        warn!(
            secrets_path = %secrets_path,
            "secrets path does not exist"
        );
        return Ok(secrets);
    }
    
    for entry in fs::read_dir(secrets_path)? {
        let entry = entry?;
        let path = entry.path();
        
        if path.is_file() {
            if let Some(file_name) = path.file_name().and_then(|n| n.to_str()) {
                let content = fs::read_to_string(&path)?;
                secrets.insert(file_name.to_string(), content.trim().to_string());
            }
        }
    }
    
    Ok(secrets)
}

fn resolve_watchers(config: &Config, secrets: &HashMap<String, String>) -> Result<Vec<ResolvedWatcher>> {
    let mut resolved_watchers = Vec::new();
    
    for watcher in &config.watchers {
        let mut resolved_webhooks = Vec::new();
        
        for webhook in &watcher.webhooks {
            let auth_token = secrets.get(&webhook.auth_token_key)
                .ok_or_else(|| anyhow::anyhow!("Auth token '{}' not found in secrets", webhook.auth_token_key))?;
            
            resolved_webhooks.push(ResolvedWebhook {
                url: webhook.url.clone(),
                auth_token: auth_token.clone(),
            });
        }
        
        resolved_watchers.push(ResolvedWatcher {
            name: watcher.name.clone(),
            deployment_name: watcher.deployment_name.clone(),
            namespace: watcher.namespace.clone(),
            webhooks: resolved_webhooks,
        });
    }
    
    Ok(resolved_watchers)
}

async fn watch_deployment(client: Client, watcher: ResolvedWatcher) -> Result<()> {
    info!(
        watcher_name = %watcher.name,
        deployment_name = %watcher.deployment_name,
        namespace = %watcher.namespace,
        "starting watcher"
    );
    
    let deployments: Api<Deployment> = Api::namespaced(client, &watcher.namespace);
    
    let wp = WatchParams::default()
        .fields(&format!("metadata.name={}", watcher.deployment_name));
    
    let mut stream = deployments.watch(&wp, "0").await?.boxed();
    
    while let Some(event) = stream.next().await {
        match event {
            Ok(WatchEvent::Added(deployment)) => {
                info!(
                    watcher_name = %watcher.name,
                    deployment_name = deployment.metadata.name.as_ref().unwrap(),
                    "deployment added"
                );
                send_webhooks(&watcher, "ADDED", &deployment).await;
            }
            Ok(WatchEvent::Modified(deployment)) => {
                info!(
                    watcher_name = %watcher.name,
                    deployment_name = deployment.metadata.name.as_ref().unwrap(),
                    "deployment modified"
                );
                send_webhooks(&watcher, "MODIFIED", &deployment).await;
            }
            Ok(WatchEvent::Deleted(deployment)) => {
                info!(
                    watcher_name = %watcher.name,
                    deployment_name = deployment.metadata.name.as_ref().unwrap(),
                    "deployment deleted"
                );
                send_webhooks(&watcher, "DELETED", &deployment).await;
            }
            Ok(WatchEvent::Bookmark(_)) => {}
            Ok(WatchEvent::Error(e)) => {
                error!(
                    watcher_name = %watcher.name,
                    error = ?e,
                    "watch error"
                );
            }
            Err(e) => {
                error!(
                    watcher_name = %watcher.name,
                    error = ?e,
                    "stream error"
                );
                break;
            }
        }
    }
    
    Ok(())
}

async fn send_webhooks(watcher: &ResolvedWatcher, event_type: &str, deployment: &Deployment) {
    let payload = json!({
        "watcher_name": watcher.name,
        "event_type": event_type,
        "deployment": {
            "name": deployment.metadata.name,
            "namespace": deployment.metadata.namespace,
            "labels": deployment.metadata.labels,
            "annotations": deployment.metadata.annotations,
            "replicas": deployment.spec.as_ref().and_then(|s| s.replicas),
            "ready_replicas": deployment.status.as_ref().and_then(|s| s.ready_replicas),
            "available_replicas": deployment.status.as_ref().and_then(|s| s.available_replicas),
            "conditions": deployment.status.as_ref().map(|s| &s.conditions),
        },
        "timestamp": chrono::Utc::now().to_rfc3339(),
    });
    
    let client = reqwest::Client::new();
    
    for webhook in &watcher.webhooks {
        let webhook_url = webhook.url.clone();
        let auth_token = webhook.auth_token.clone();
        let payload_clone = payload.clone();
        let client_clone = client.clone();
        let event_type_str = event_type.to_string();
        let watcher_name_str = watcher.name.clone();
        
        tokio::spawn(async move {
            match client_clone
                .post(&webhook_url)
                .header("Authorization", format!("Bearer {}", auth_token))
                .header("Content-Type", "application/json")
                .json(&payload_clone)
                .send()
                .await
            {
                Ok(response) => {
                    if response.status().is_success() {
                        info!(
                            watcher_name = watcher_name_str,
                            event_type = event_type_str,
                            webhook_url = webhook_url,
                            "webhook sent successfully"
                        );
                    } else {
                        let status_code = response.status().to_string();
                        let response_text = response.text().await.unwrap_or_default();
                        warn!(
                            watcher_name = watcher_name_str,
                            status = status_code,
                            webhook_url = webhook_url,
                            response_text = response_text,
                            "webhook failed"
                        );
                    }
                }
                Err(e) => {
                    let error_msg = e.to_string();
                    error!(
                        watcher_name = watcher_name_str,
                        webhook_url = webhook_url,
                        error = error_msg,
                        "failed to send webhook"
                    );
                }
            }
        });
    }
}
