# ============================================================================
# OUTPUTS: Re-exportar outputs del módulo base + outputs específicos
# ============================================================================

output "instance_id" {
  description = "ID de la instancia VM"
  value       = module.vm_base.instance_id
}

output "instance_name" {
  description = "Nombre de la instancia VM"
  value       = module.vm_base.instance_name
}

output "instance_zone" {
  description = "Zona de la instancia"
  value       = module.vm_base.instance_zone
}

output "internal_ip" {
  description = "IP interna de la instancia"
  value       = module.vm_base.internal_ip
}

output "external_ip" {
  description = "IP externa de la instancia (null si no tiene IP pública). Si se usa IP estática, contiene la dirección de la IP estática."
  value       = module.vm_base.external_ip
}

output "static_public_ip_name" {
  description = "Nombre del recurso de IP pública estática (null si no se usa IP estática). Útil para referenciar el recurso directamente."
  value       = module.vm_base.static_public_ip_name
}

output "self_link" {
  description = "Self link de la instancia"
  value       = module.vm_base.self_link
}

output "ssh_command" {
  description = "Comando SSH para conectarse vía IAP (si no tiene IP pública)"
  value       = module.vm_base.ssh_command
}

output "copy_deployment_scripts_info" {
  description = <<-EOT
    Información para copiar scripts de despliegue a la VM (solo si deployment_scripts está configurado).

    Ejecuta manualmente después de terraform apply:
    ./modules/vm-docker/scripts/copy_deployment_scripts.sh <instance_name> <zone> <project_id> <destination> <source> <user>

    Requiere: gcloud CLI instalado y autenticado, y VM con tag "allow-iap-ssh"
  EOT
  value = var.deployment_scripts != "" ? {
    instance_name = module.vm_base.instance_name
    zone          = var.zone
    project_id    = var.project_id
    destination   = var.deployment_scripts_destination
    source        = var.deployment_scripts
    user          = var.use_ubuntu_image ? "ubuntu" : "user"
    script_path   = "modules/vm-docker/scripts/copy_deployment_scripts.sh"
  } : null
}
