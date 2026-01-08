# ============================================================================
# CLUSTER GKE PRINCIPAL
# ============================================================================

resource "google_container_cluster" "gke_cluster" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  # Versión de Kubernetes
  min_master_version = var.kubernetes_version != "" ? var.kubernetes_version : null

  # Eliminar el node pool por defecto (crearemos uno personalizado)
  remove_default_node_pool = true
  initial_node_count       = var.initial_node_count

  # Network configuration
  network    = data.google_compute_subnetwork.gke_subnet[0].network
  subnetwork = var.gke_subnet_name

  # IP ranges para pods y services
  ip_allocation_policy {
    cluster_secondary_range_name  = var.gke_pods_range_name
    services_secondary_range_name = var.gke_services_range_name
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.gke_master_cidr
  }

  # Master authorized networks
  dynamic "master_authorized_networks_config" {
    for_each = length(local.master_authorized_networks_config) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = local.master_authorized_networks_config
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # Network policy
  network_policy {
    enabled = var.enable_network_policy
  }

  # Addons
  addons_config {
    http_load_balancing {
      disabled = !var.enable_http_load_balancing
    }
    horizontal_pod_autoscaling {
      disabled = !var.enable_horizontal_pod_autoscaling
    }
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = var.workload_identity_pool != "" ? var.workload_identity_pool : "${var.project_id}.svc.id.goog"
  }

  # Maintenance window
  # GKE requiere al menos 4 horas de ventana disponible dentro de 48 horas
  # Usamos una ventana diaria que se repite cada día para cumplir con este requisito
  maintenance_policy {
    recurring_window {
      start_time = local.maintenance_window_start_time
      end_time   = local.maintenance_window_end_time
      # Usar ventana diaria en lugar de semanal para cumplir con requisitos de GKE
      # Alternativamente, si prefieres semanal, asegúrate de que la ventana sea >= 4 horas
      recurrence = "FREQ=DAILY"
    }
  }

  # Deletion protection
  # IMPORTANTE: Debe ser false para poder destruir el cluster
  deletion_protection = var.deletion_protection

  # Labels
  resource_labels = merge(
    {
      managed_by = "terraform"
    },
    var.labels
  )

  # Lifecycle
  lifecycle {
    ignore_changes = [
      node_config[0].service_account,
    ]
  }
}
