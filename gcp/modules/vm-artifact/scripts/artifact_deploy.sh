#!/bin/bash
set -euo pipefail

# Log para debugging
exec > >(tee /var/log/artifact-deploy.log) 2>&1
echo "=== Iniciando despliegue desde Artifact Registry ==="
echo "Fecha: $(date)"

# Autenticar con Artifact Registry usando gcloud
echo "Región de Artifact Registry: ${artifact_region}"

# Configurar Docker para usar gcloud como helper de credenciales
gcloud auth configure-docker ${artifact_region}-docker.pkg.dev --quiet || true

# Alternativa: usar token directamente (más seguro)
# gcloud auth print-access-token | docker login -u oauth2accesstoken --password-stdin https://${artifact_region}-docker.pkg.dev || true

# Esperar a que Docker esté listo
sleep 5

# Pull de la imagen
echo "Pulling image: ${image_full_path}"
docker pull ${image_full_path} || {
  echo "❌ Error: No se pudo hacer pull de la imagen ${image_full_path}"
  echo "Verifica que:"
  echo "  1. La imagen existe en Artifact Registry"
  echo "  2. La Service Account tiene permisos para leer imágenes"
  echo "  3. El nombre de la imagen es correcto"
  exit 1
}

# Ejecutar contenedor
echo "Running container..."
${docker_run_command}

echo "✅ Contenedor iniciado exitosamente"
