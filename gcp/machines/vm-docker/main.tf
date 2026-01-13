# ============================================================================
# CONFIGURACIÓN TERRAFORM Y PROVIDERS
# ============================================================================

terraform {
  required_version = ">= 1.14.2"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }

  # Por defecto usa backend local (estado en .terraform/).
  # Usa backend GCS (recomendado para producción):
  #
  backend "gcs" {
    bucket = "roax-terraform-state-stg"
    prefix = "vm-docker/monolith"
  }
}

provider "google" {
  project     = var.project_id
  region      = var.region
  credentials = var.credentials_file != null ? file("${path.root}/../keys/${var.credentials_file}") : null
}

# ============================================================================
# DATA SOURCES: Infraestructura compartida
# ============================================================================
# Data sources para obtener información de la infraestructura compartida
# Solo se usa si shared_infra_state_bucket y shared_infra_state_prefix están definidos
# Si prefieres, puedes especificar los valores directamente en terraform.tfvars
# Ver: instance/examples/docs/REMOTE_SETUP.md para más detalles

data "terraform_remote_state" "shared_infra" {
  count = var.shared_infra_state_bucket != null && var.shared_infra_state_prefix != null ? 1 : 0

  backend = "gcs"
  config = {
    bucket = var.shared_infra_state_bucket
    prefix = var.shared_infra_state_prefix
  }
}

# ============================================================================
# MÓDULO VM-DOCKER
# ============================================================================

module "vm_docker" {
  # Módulo local (por defecto, para desarrollo)
  # Usar fuente local para probar los cambios nuevos antes de hacer push al repo
  source = "../../modules/vm-docker"

  # Repositorio PÚBLICO desde branch (main) / tag (1.0.0)
  # source = "git::https://github.com/tu-org/terraform-gcp.git//instance/modules/vm-docker?ref=main"

  # Repositorio PRIVADO usando PAT en URL
  # ⚠️  ADVERTENCIA: El token queda visible en el código - no subir al repo
  # source = "git::https://ghp_xxxxxxxxxxxx@github.com/tu-org/terraform-gcp.git//instance/modules/vm-docker?ref=v1.0.0"

  project_id              = var.project_id
  region                  = var.region
  zone                    = var.zone
  instance_name           = var.instance_name
  machine_type            = var.machine_type
  vm_subnet_name          = local.vm_subnet_name
  service_account_email   = local.service_account_email
  tags                    = local.tags_combined
  labels                  = var.labels
  boot_disk_size          = var.boot_disk_size
  boot_disk_type          = var.boot_disk_type
  enable_public_ip        = var.enable_public_ip
  static_public_ip        = var.static_public_ip
  static_internal_ip      = var.static_internal_ip
  metadata_startup_script = var.metadata_startup_script
  ssh_keys                = local.ssh_keys_combined
  install_docker_compose  = var.install_docker_compose
  install_certbot         = var.install_certbot
  use_ubuntu_image        = var.use_ubuntu_image
  deployment_scripts      = var.deployment_scripts
  microservices           = var.microservices
  environment             = var.environment
}
