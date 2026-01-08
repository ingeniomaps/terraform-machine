# ============================================================================
# IP ESTÁTICA PÚBLICA (OPCIONAL)
# ============================================================================

resource "google_compute_address" "static_public_ip" {
  count = var.enable_public_ip && var.static_public_ip != null ? 1 : 0

  name         = var.static_public_ip
  address_type = "EXTERNAL"
  region       = var.region
  project      = var.project_id

  description = "IP estática pública para ${var.instance_name}"

  labels = merge(
    {
      managed_by = "terraform"
      purpose    = var.purpose_label
    },
    var.labels
  )
}
