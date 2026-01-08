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

output "docker_image_path" {
  description = "Ruta completa de la imagen Docker"
  value       = local.image_full_path
}

output "container_url" {
  description = "URL para acceder al contenedor (si tiene IP pública)"
  value       = module.vm_base.external_ip != null ? "http://${module.vm_base.external_ip}:${var.host_port}" : null
}

output "ssh_command" {
  description = "Comando SSH para conectarse vía IAP (si no tiene IP pública)"
  value       = module.vm_base.ssh_command
}
