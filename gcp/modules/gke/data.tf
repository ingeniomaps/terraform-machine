# ============================================================================
# DATA SOURCES
# ============================================================================

# Data source para obtener información de la subnet GKE
# Solo se consulta si gke_subnet_name no es null (GKE habilitado)
data "google_compute_subnetwork" "gke_subnet" {
  count = var.gke_subnet_name != null && var.gke_subnet_name != "" ? 1 : 0

  name    = var.gke_subnet_name
  region  = var.region
  project = var.project_id
}
