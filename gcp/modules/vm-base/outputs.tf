# ============================================================================
# OUTPUTS
# ============================================================================

output "instance_id" {
  description = "ID de la instancia"
  value       = google_compute_instance.vm.id
}

output "instance_name" {
  description = "Nombre de la instancia"
  value       = google_compute_instance.vm.name
}

output "instance_zone" {
  description = "Zona de la instancia"
  value       = google_compute_instance.vm.zone
}

output "internal_ip" {
  description = "IP interna de la instancia"
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "external_ip" {
  description = "IP externa de la instancia (null si no tiene IP pública). Si se usa IP estática, contiene la dirección de la IP estática."
  value       = var.enable_public_ip ? google_compute_instance.vm.network_interface[0].access_config[0].nat_ip : null
}

output "static_public_ip_name" {
  description = "Nombre del recurso de IP pública estática (null si no se usa IP estática). Útil para referenciar el recurso directamente."
  value       = var.enable_public_ip && var.static_public_ip != null ? google_compute_address.static_public_ip[0].name : null
}

output "ssh_command" {
  description = "Comando SSH para conectarse. Si tiene IP pública, usa SSH directo. Si no, usa IAP."
  value       = var.enable_public_ip ? "ssh -i /ruta/a/tu/clave.pem ubuntu@${google_compute_instance.vm.network_interface[0].access_config[0].nat_ip}" : "gcloud compute ssh ${google_compute_instance.vm.name} --zone=${google_compute_instance.vm.zone} --project=${var.project_id} --tunnel-through-iap"
}

output "self_link" {
  description = "Self link de la instancia"
  value       = google_compute_instance.vm.self_link
}
