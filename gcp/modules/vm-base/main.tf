# ============================================================================
# RECURSO PRINCIPAL: INSTANCIA VM BASE
# ============================================================================

resource "google_compute_instance" "vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  tags = var.tags

  labels = merge(
    {
      managed_by = "terraform"
      purpose    = var.purpose_label
    },
    var.labels
  )

  boot_disk {
    initialize_params {
      image = var.vm_image
      size  = var.boot_disk_size
      type  = var.boot_disk_type
    }
  }

  network_interface {
    subnetwork = var.vm_subnet_name
    # IP interna estática si se especifica, sino automática
    network_ip = var.static_internal_ip

    # IP pública solo si está habilitada
    dynamic "access_config" {
      for_each = var.enable_public_ip ? [1] : []
      content {
        # IP estática si se especificó, sino ephemeral
        nat_ip = var.static_public_ip != null ? google_compute_address.static_public_ip[0].address : null
      }
    }
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  metadata = merge(
    var.startup_script != "" ? {
      startup-script = var.startup_script
    } : {},
    length(var.ssh_keys) > 0 ? {
      ssh-keys = join("\n", var.ssh_keys)
    } : {}
  )

  allow_stopping_for_update = true
}
