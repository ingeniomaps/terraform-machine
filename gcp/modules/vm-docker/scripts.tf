locals {

  docker_install_script = trimspace(templatefile(
    "${path.module}/scripts/docker_install.sh",
    {
      install_docker_compose = var.install_docker_compose && var.use_ubuntu_image
      docker_compose_version = var.docker_compose_version
    }
  ))

  certbot_install_script = (
    var.install_certbot && var.use_ubuntu_image
    ) ? trimspace(templatefile(
      "${path.module}/scripts/certbot_install.sh",
      {}
  )) : ""

  # Procesar microservicios: si env_file es una ruta a archivo, leer su contenido
  # Si parece una ruta (contiene "/" o empieza con "./" o "../") y el archivo existe, leerlo
  # De lo contrario, se trata como contenido directo
  processed_microservices = [
    for service in var.microservices : {
      name     = service.name
      repo_url = service.repo_url
      branch   = service.branch
      env_file = (
        # Detectar si es una ruta: contiene "/" o empieza con "./" o "../"
        (can(regex("^[./]", service.env_file)) || can(regex("/", service.env_file))) &&
        # Verificar que el archivo existe (ruta relativa desde el directorio donde está terraform.tfvars)
        fileexists("${path.root}/${service.env_file}")
      ) ? file("${path.root}/${service.env_file}") : service.env_file
    }
  ]

  microservices_deploy_script = length(var.microservices) > 0 ? trimspace(templatefile(
    "${path.module}/scripts/microservices_deploy.sh",
    {
      microservices = local.processed_microservices
    }
  )) : ""

  combined_startup_script = join("\n\n", compact([
    "#!/bin/bash",
    "set -euo pipefail",
    "exec > >(tee /var/log/startup-script.log) 2>&1",
    "",
    local.docker_install_script,
    local.certbot_install_script,
    local.microservices_deploy_script
  ]))

  startup_script = var.metadata_startup_script != "" ? join("\n\n", [
    local.combined_startup_script,
    "# Script personalizado adicional",
    trimspace(var.metadata_startup_script)
  ]) : local.combined_startup_script

  vm_image = (
    var.use_ubuntu_image
    ? "projects/ubuntu-os-cloud/global/images/family/${var.ubuntu_image_family}"
    : "projects/cos-cloud/global/images/family/cos-stable"
  )

}
