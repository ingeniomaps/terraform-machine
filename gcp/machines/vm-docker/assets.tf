# ============================================================================
# ASSETS: Archivos adicionales para la VM
# ============================================================================
# Este archivo maneja la subida de archivos desde la carpeta assets/ a la VM
# usando Terraform (null_resource con local-exec), no scripts bash externos.
#
# Uso:
# 1. Coloca tus archivos (backups, imágenes, PDFs, etc.) en la carpeta assets/
# 2. Ejecuta terraform apply
# 3. Los archivos se copiarán automáticamente a /home/ubuntu/assets/ en la VM

locals {
  # Ruta local de la carpeta assets
  assets_source_dir = "${path.module}/assets"
  
  # Ruta destino en la VM
  assets_destination_dir = "/home/ubuntu/assets"
  
  # Verificar si la carpeta assets existe
  assets_dir_exists = fileexists("${local.assets_source_dir}/README.md")
}

# Recurso null para copiar archivos después de crear la VM
# Solo se crea si la carpeta assets existe
resource "null_resource" "copy_assets" {
  count = local.assets_dir_exists ? 1 : 0

  triggers = {
    # Trigger para detectar cambios en la carpeta assets
    # Usamos el hash de la carpeta completa como trigger
    assets_dir_hash = try(
      sha256(join("", [
        for f in fileset(local.assets_source_dir, "**") : "${f}:${try(filemd5("${local.assets_source_dir}/${f}"), "dir")}"
      ])),
      ""
    )
    instance_name = module.vm_docker.instance_name
    zone          = var.zone
  }

  # Depender de que la VM esté creada
  depends_on = [module.vm_docker]

  # Ejecutar comando local para copiar archivos usando gcloud
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Copiando archivos desde ${local.assets_source_dir} a la VM..."
      
      # Crear directorio destino en la VM
      gcloud compute ssh ${module.vm_docker.instance_name} \
        --zone=${var.zone} \
        --project=${var.project_id} \
        --command="sudo mkdir -p ${local.assets_destination_dir} && sudo chown ubuntu:ubuntu ${local.assets_destination_dir}" \
        --tunnel-through-iap || true
      
      # Copiar archivos usando gcloud compute scp (recurse copia todo el contenido)
      gcloud compute scp \
        --recurse \
        --zone=${var.zone} \
        --project=${var.project_id} \
        --tunnel-through-iap \
        ${local.assets_source_dir}/ \
        ubuntu@${module.vm_docker.instance_name}:${local.assets_destination_dir}/ || {
          echo "Warning: Error al copiar archivos. Verifica que gcloud esté instalado y configurado, y que la VM tenga el tag allow-iap-ssh"
          exit 0
        }
      
      echo "Archivos copiados exitosamente a ${local.assets_destination_dir}/"
    EOT
  }
}
