# ============================================================================
# SCRIPTS DE INSTALACIÓN Y DESPLIEGUE
# ============================================================================

locals {
  # Construir ruta completa de la imagen
  image_full_path = var.docker_image_full_path != "" ? var.docker_image_full_path : "${var.artifact_registry_url}/${var.docker_image}"

  # Construir variables de entorno para Docker
  docker_env_string = length(var.docker_env_vars) > 0 ? join(" ", [
    for k, v in var.docker_env_vars : "-e ${k}=${v}"
  ]) : ""

  # Construir comando Docker
  docker_run_command = var.docker_command != "" ? var.docker_command : "docker run -d --restart=${var.restart_policy} -p ${var.host_port}:${var.container_port} ${local.docker_env_string} ${local.image_full_path}"

  # Script de instalación de Docker
  docker_install_script = var.use_ubuntu_image ? trimspace(templatefile(
    "${path.module}/scripts/docker_install.sh",
    {}
  )) : ""

  # Extraer región del URL de Artifact Registry
  artifact_region = try(
    regex("https?://([^-]+)-docker\\.pkg\\.dev", var.artifact_registry_url)[0],
    "us-central1"
  )

  # Script de despliegue desde Artifact Registry
  artifact_deploy_script = trimspace(templatefile(
    "${path.module}/scripts/artifact_deploy.sh",
    {
      artifact_registry_url = var.artifact_registry_url
      artifact_region       = local.artifact_region
      image_full_path       = local.image_full_path
      docker_run_command    = local.docker_run_command
    }
  ))

  # Health check script (opcional)
  health_check_script = var.health_check_path != "" ? trimspace(templatefile(
    "${path.module}/scripts/health_check.sh",
    {
      health_check_port = var.health_check_port > 0 ? var.health_check_port : var.container_port
      health_check_path = var.health_check_path
      image_full_path   = local.image_full_path
    }
  )) : ""

  # Script de inicio completo
  combined_startup_script = join("\n\n", compact([
    "#!/bin/bash",
    "set -euo pipefail",
    "exec > >(tee /var/log/startup-script.log) 2>&1",
    "",
    local.docker_install_script,
    local.artifact_deploy_script,
    local.health_check_script
  ]))

  # El script de inicio es el combinado (no hay metadata_startup_script en vm-artifact)
  startup_script = local.combined_startup_script

  # Imagen a usar según configuración
  vm_image = var.use_ubuntu_image ? "projects/ubuntu-os-cloud/global/images/family/${var.ubuntu_image_family}" : "projects/cos-cloud/global/images/family/cos-stable"
}
