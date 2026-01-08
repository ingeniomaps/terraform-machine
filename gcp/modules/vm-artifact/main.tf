# ============================================================================
# MÓDULO BASE: VM CONFIGURACIÓN COMÚN
# ============================================================================

module "vm_base" {
  source = "../vm-base"

  project_id            = var.project_id
  region                = var.region
  zone                  = var.zone
  instance_name         = var.instance_name
  machine_type          = var.machine_type
  vm_subnet_name        = var.vm_subnet_name
  service_account_email = var.service_account_email
  tags                  = var.tags
  labels                = var.labels
  boot_disk_size        = var.boot_disk_size
  boot_disk_type        = var.boot_disk_type
  enable_public_ip      = var.enable_public_ip
  static_public_ip      = var.static_public_ip
  static_internal_ip    = var.static_internal_ip
  vm_image              = local.vm_image
  startup_script        = local.startup_script
  ssh_keys              = []
  purpose_label         = "docker-container"
}
