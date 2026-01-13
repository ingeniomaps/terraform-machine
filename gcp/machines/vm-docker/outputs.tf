# ============================================================================
# OUTPUTS: Re-exportar outputs del módulo vm-docker
# ============================================================================

output "instance_id" {
  description = "ID de la instancia VM"
  value       = module.vm_docker.instance_id
}

output "instance_name" {
  description = "Nombre de la instancia VM"
  value       = module.vm_docker.instance_name
}

output "instance_zone" {
  description = "Zona de la instancia"
  value       = module.vm_docker.instance_zone
}

output "internal_ip" {
  description = "IP interna de la instancia"
  value       = module.vm_docker.internal_ip
}

output "external_ip" {
  description = "IP externa de la instancia (null si no tiene IP pública). Si se usa IP estática, contiene la dirección de la IP estática."
  value       = module.vm_docker.external_ip
}

output "static_public_ip_name" {
  description = "Nombre del recurso de IP pública estática (null si no se usa IP estática). Útil para referenciar el recurso directamente."
  value       = module.vm_docker.static_public_ip_name
}

output "self_link" {
  description = "Self link de la instancia"
  value       = module.vm_docker.self_link
}

output "ssh_command" {
  description = "Comando SSH para conectarse vía IAP (si no tiene IP pública) o directamente (si tiene IP pública)"
  value       = module.vm_docker.ssh_command
}

output "ssh_private_key_path" {
  description = "Ruta al archivo de clave privada SSH (.pem) generado por Terraform"
  value       = local_file.private_key.filename
  sensitive   = false
}

output "ssh_public_key" {
  description = "Clave pública SSH generada (para referencia)"
  value       = tls_private_key.vm_ssh_key.public_key_openssh
  sensitive   = false
}

output "project_id" {
  description = "ID del proyecto GCP (para scripts de restauración)"
  value       = var.project_id
}

# ============================================================================
# OUTPUTS: Información de red desde shared-infra
# ============================================================================

output "vpc_name" {
  description = "Nombre de la VPC (obtenido de shared-infra si está disponible)"
  value       = local.vpc_name
}

output "vm_subnet_name" {
  description = "Nombre de la subnet para VMs (obtenido de shared-infra si está disponible)"
  value       = local.vm_subnet_name
}

output "vm_subnet_cidr" {
  description = "CIDR de la subnet para VMs (obtenido de shared-infra si está disponible, útil para validar IPs estáticas)"
  value       = local.vm_subnet_cidr
}

output "cloud_nat_name" {
  description = "Nombre del Cloud NAT (obtenido de shared-infra si está disponible). Útil cuando enable_public_ip = false, ya que la VM necesita Cloud NAT para acceso saliente a Internet."
  value       = local.cloud_nat_name
}

output "network_name" {
  description = "Nombre de la red (workspace-env, obtenido de shared-infra si está disponible)"
  value       = local.network_name
}

output "network_tags" {
  description = "Network tags que deben usarse en recursos (obtenido de shared-infra si está disponible, incluye allow_iap_ssh y allow_ssh con el formato correcto)"
  value       = local.network_tags
}
