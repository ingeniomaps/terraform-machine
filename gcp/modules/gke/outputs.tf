output "cluster_id" {
  description = "ID del cluster GKE"
  value       = google_container_cluster.gke_cluster.id
}

output "cluster_name" {
  description = "Nombre del cluster GKE"
  value       = google_container_cluster.gke_cluster.name
}

output "cluster_location" {
  description = "Ubicación del cluster"
  value       = google_container_cluster.gke_cluster.location
}

output "cluster_endpoint" {
  description = "Endpoint del control plane"
  value       = google_container_cluster.gke_cluster.endpoint
  sensitive   = true
}

output "kubectl_command" {
  description = "Comando para configurar kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.gke_cluster.name} --region=${google_container_cluster.gke_cluster.location} --project=${var.project_id}"
}

output "node_pool_id" {
  description = "ID del node pool"
  value       = google_container_node_pool.default_pool.id
}

output "node_pool_name" {
  description = "Nombre del node pool"
  value       = google_container_node_pool.default_pool.name
}

output "workload_identity_pool" {
  description = "Workload Identity Pool configurado"
  value       = google_container_cluster.gke_cluster.workload_identity_config[0].workload_pool
}

output "autoscaling_min_nodes" {
  description = "Número mínimo de nodos (auto-scaling). Null si auto-scaling está deshabilitado."
  value       = var.enable_autoscaling ? var.min_node_count : null
}

output "autoscaling_max_nodes" {
  description = "Número máximo de nodos (auto-scaling). Null si auto-scaling está deshabilitado."
  value       = var.enable_autoscaling ? var.max_node_count : null
}

output "current_node_count" {
  description = "Número actual de nodos en el node pool"
  value       = google_container_node_pool.default_pool.node_count
}

output "cluster_ca_certificate" {
  description = "CA certificate del cluster (para kubectl)"
  value       = google_container_cluster.gke_cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}
