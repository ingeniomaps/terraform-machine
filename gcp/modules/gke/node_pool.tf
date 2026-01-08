# ============================================================================
# NODE POOL CON AUTO-SCALING
# ============================================================================

resource "google_container_node_pool" "default_pool" {
  name       = var.node_pool_name
  location   = var.region
  cluster    = google_container_cluster.gke_cluster.name
  project    = var.project_id
  node_count = var.initial_node_count

  # Auto-scaling: Escala automáticamente entre min_node_count y max_node_count
  # Solo se crea el bloque si enable_autoscaling es true
  dynamic "autoscaling" {
    for_each = var.enable_autoscaling ? [1] : []
    content {
      min_node_count = var.min_node_count
      max_node_count = var.max_node_count
    }
  }

  # Gestión automática de nodos
  management {
    auto_repair  = var.enable_autorepair
    auto_upgrade = var.enable_autoupgrade
  }

  node_config {
    machine_type    = var.node_machine_type
    disk_size_gb    = var.node_disk_size
    disk_type       = var.node_disk_type
    service_account = var.service_account_email != null ? var.service_account_email : ""
    preemptible     = false

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Labels
    labels = merge(
      {
        managed_by = "terraform"
      },
      var.labels
    )

    # Tags
    tags = var.network_tags
  }

  lifecycle {
    ignore_changes = [
      node_count,
    ]
  }
}
