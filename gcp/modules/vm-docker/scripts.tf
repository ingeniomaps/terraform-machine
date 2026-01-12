locals {

  # ============================================================================
  # SCRIPTS DE INSTALACIÓN
  # ============================================================================

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

  # ============================================================================
  # PROCESAMIENTO DE MICROSERVICIOS
  # ============================================================================
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
      launch_command = service.launch_command # Siempre incluido, puede ser null
    }
  ]

  microservices_deploy_script = length(var.microservices) > 0 ? trimspace(templatefile(
    "${path.module}/scripts/microservices_deploy.sh",
    {
      microservices = local.processed_microservices
    }
  )) : ""

  # ============================================================================
  # SCRIPTS DE ACTUALIZACIÓN (se copian durante startup)
  # ============================================================================

  update_microservices_script = file("${path.module}/scripts/update_microservices.sh")

  helper_update_services_script = file("${path.module}/scripts/helper_update_services.sh")

  watch_metadata_script = file("${path.module}/scripts/watch_metadata.sh")

  diagnose_update_script = file("${path.module}/scripts/diagnose_update.sh")

  # ============================================================================
  # JSON DE MICROSERVICIOS PARA METADATA
  # ============================================================================
  # Filtrar campos null antes de codificar para evitar incluir "launch_command": null en el JSON

  microservices_json = jsonencode([
    for service in local.processed_microservices : merge(
      {
        name     = service.name
        repo_url = service.repo_url
        branch   = service.branch
        env_file = service.env_file
      },
      # Solo incluir launch_command si no es null y no está vacío
      # launch_command es obligatorio pero puede ser null
      service.launch_command != null && trimspace(service.launch_command) != "" ? {
        launch_command = service.launch_command
      } : {}
    )
  ])

  # ============================================================================
  # SCRIPT DE STARTUP COMBINADO
  # ============================================================================
  # Este script se ejecuta cuando la VM inicia por primera vez
  # Organizado en secciones claras para facilitar el mantenimiento

  combined_startup_script = join("\n\n", compact([
    # ==========================================================================
    # ENCABEZADO Y CONFIGURACIÓN INICIAL
    # ==========================================================================
    "#!/bin/bash",
    "set -euo pipefail",
    "exec > >(tee /var/log/startup-script.log) 2>&1",
    "",
    # Configurar directorio home de ubuntu
    "echo 'Configurando directorio home de ubuntu...'",
    "mkdir -p /home/ubuntu",
    "chown ubuntu:ubuntu /home/ubuntu || true",
    "chmod 755 /home/ubuntu || true",
    "",
    # Configurar Git globalmente para evitar "dubious ownership"
    "if [ -d /home/ubuntu ]; then",
    "  sudo -u ubuntu git config --global --add safe.directory /home/ubuntu || true",
    "fi",
    "",
    # ==========================================================================
    # INSTALACIÓN DE DEPENDENCIAS
    # ==========================================================================
    local.docker_install_script,
    local.certbot_install_script,
    "",
    # ==========================================================================
    # COPIAR SCRIPTS DE ACTUALIZACIÓN DE MICROSERVICIOS
    # ==========================================================================
    "echo 'Copiando scripts de actualización de microservicios...'",
    "mkdir -p /opt/scripts",
    "chown ubuntu:ubuntu /opt/scripts || true",
    "chmod 755 /opt/scripts || true",
    "",
    # Copiar update_microservices.sh
    "cat > /opt/scripts/update_microservices.sh <<'UPDATE_SCRIPT_EOF'",
    local.update_microservices_script,
    "UPDATE_SCRIPT_EOF",
    "chmod +x /opt/scripts/update_microservices.sh",
    "chown ubuntu:ubuntu /opt/scripts/update_microservices.sh || true",
    "",
    # Copiar helper_update_services.sh
    "cat > /opt/scripts/helper_update_services.sh <<'HELPER_SCRIPT_EOF'",
    local.helper_update_services_script,
    "HELPER_SCRIPT_EOF",
    "chmod +x /opt/scripts/helper_update_services.sh",
    "chown ubuntu:ubuntu /opt/scripts/helper_update_services.sh || true",
    "",
    # Copiar watch_metadata.sh
    "cat > /opt/scripts/watch_metadata.sh <<'WATCH_SCRIPT_EOF'",
    local.watch_metadata_script,
    "WATCH_SCRIPT_EOF",
    "chmod +x /opt/scripts/watch_metadata.sh",
    "chown ubuntu:ubuntu /opt/scripts/watch_metadata.sh || true",
    "",
    # Copiar diagnose_update.sh
    "cat > /opt/scripts/diagnose_update.sh <<'DIAGNOSE_SCRIPT_EOF'",
    local.diagnose_update_script,
    "DIAGNOSE_SCRIPT_EOF",
    "chmod +x /opt/scripts/diagnose_update.sh",
    "chown ubuntu:ubuntu /opt/scripts/diagnose_update.sh || true",
    "",
    # Asegurar permisos de todos los scripts
    "chown -R ubuntu:ubuntu /opt/scripts || true",
    "echo 'Scripts de actualización copiados'",
    "",
    # ==========================================================================
    # CONFIGURAR SERVICIO SYSTEMD PARA MONITOREO DE METADATA
    # ==========================================================================
    "echo 'Configurando servicio para monitoreo automático de metadata...'",
    "",
    # Crear servicio systemd
    "cat > /etc/systemd/system/watch-metadata.service <<'SERVICE_EOF'",
    "[Unit]",
    "Description=Monitor metadata changes and update microservices",
    "After=network.target",
    "",
    "[Service]",
    "Type=oneshot",
    "User=ubuntu",
    "Group=ubuntu",
    "WorkingDirectory=/home/ubuntu",
    "ExecStart=/opt/scripts/watch_metadata.sh",
    "StandardOutput=journal",
    "StandardError=journal",
    "",
    "[Install]",
    "WantedBy=multi-user.target",
    "SERVICE_EOF",
    "",
    # Crear timer systemd
    "cat > /etc/systemd/system/watch-metadata.timer <<'TIMER_EOF'",
    "[Unit]",
    "Description=Timer for metadata monitoring",
    "Requires=watch-metadata.service",
    "",
    "[Timer]",
    "OnBootSec=2min",
    "OnUnitActiveSec=1min",
    "AccuracySec=5s",
    "",
    "[Install]",
    "WantedBy=timers.target",
    "TIMER_EOF",
    "",
    # Habilitar y iniciar el timer
    "systemctl daemon-reload",
    "systemctl enable watch-metadata.timer",
    "systemctl start watch-metadata.timer",
    "echo 'Servicio de monitoreo de metadata configurado y activado'",
    "",
    # ==========================================================================
    # CONFIGURAR LOGS
    # ==========================================================================
    "touch /var/log/watch-metadata.log || true",
    "chown ubuntu:ubuntu /var/log/watch-metadata.log || true",
    "chmod 664 /var/log/watch-metadata.log || true",
    "",
    # ==========================================================================
    # EJECUTAR VERIFICACIÓN INICIAL Y DESPLIEGUE
    # ==========================================================================
    # Ejecutar inmediatamente para verificar si hay metadata inicial (como usuario ubuntu)
    "echo 'Ejecutando verificación inicial de metadata...'",
    "sudo -u ubuntu /opt/scripts/watch_metadata.sh || true",
    "",
    # Desplegar microservicios iniciales (como usuario ubuntu)
    length(var.microservices) > 0 ? join("\n", [
      "echo 'Desplegando microservicios iniciales...'",
      "sudo -u ubuntu bash <<'MICROSERVICES_DEPLOY_EOF'",
      local.microservices_deploy_script,
      "MICROSERVICES_DEPLOY_EOF"
    ]) : ""
  ]))

  # ============================================================================
  # SCRIPT DE STARTUP FINAL
  # ============================================================================
  # Combina el script base con cualquier script personalizado adicional

  startup_script = var.metadata_startup_script != "" ? join("\n\n", [
    local.combined_startup_script,
    "# Script personalizado adicional",
    trimspace(var.metadata_startup_script)
  ]) : local.combined_startup_script

  # ============================================================================
  # IMAGEN DE VM
  # ============================================================================

  vm_image = (
    var.use_ubuntu_image
    ? "projects/ubuntu-os-cloud/global/images/family/${var.ubuntu_image_family}"
    : "projects/cos-cloud/global/images/family/cos-stable"
  )

}
