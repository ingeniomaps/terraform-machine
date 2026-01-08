# ============================================================================
# PROVISIONERS: COPIA DE SCRIPTS DE DESPLIEGUE
# ============================================================================

# Null resource para copiar scripts de despliegue usando gcloud con IAP
# Nota: Usa gcloud compute scp/ssh que automáticamente usa IAP cuando está disponible
resource "null_resource" "copy_deployment_scripts" {
  # Solo crear el recurso si deployment_scripts está especificado
  count = var.deployment_scripts != "" ? 1 : 0

  # Triggers para asegurar que se ejecute cuando la VM esté lista
  # Se actualiza cuando cambia el ID de la instancia (después de crearse)
  triggers = {
    instance_id    = module.vm_base.instance_id
    instance_name  = module.vm_base.instance_name
    zone           = var.zone
    project_id     = var.project_id
    deployment_dir = var.deployment_scripts
  }

  # Usar local-exec con gcloud para copiar archivos vía IAP
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      INSTANCE_NAME="${module.vm_base.instance_name}"
      ZONE="${var.zone}"
      PROJECT="${var.project_id}"
      DEST_DIR="${var.deployment_scripts_destination}"
      SRC_DIR="${var.deployment_scripts}"
      USER="${var.use_ubuntu_image ? "ubuntu" : "user"}"

      echo "📦 Copiando scripts de despliegue a la VM..."
      echo "   Instancia: $INSTANCE_NAME"
      echo "   Zona: $ZONE"
      echo "   Origen: $SRC_DIR"
      echo "   Destino: $DEST_DIR"

      # Resolver ruta absoluta del directorio fuente
      if [ -d "$SRC_DIR" ]; then
        SRC_DIR_ABS=$(cd "$SRC_DIR" && pwd)
      else
        SRC_DIR_ABS=$(cd "$SRC_DIR" 2>/dev/null && pwd || echo "")
        if [ -z "$SRC_DIR_ABS" ]; then
          PARENT_DIR=$(cd .. && pwd)
          SRC_DIR_ABS=$(cd "$PARENT_DIR/$SRC_DIR" 2>/dev/null && pwd || echo "")
        fi
      fi

      # Validar que el directorio existe
      if [ ! -d "$SRC_DIR_ABS" ]; then
        echo "❌ Error: Directorio inválido: $SRC_DIR"
        echo "   Ruta resuelta: $SRC_DIR_ABS"
        exit 1
      fi

      echo "✅ Directorio fuente: $SRC_DIR_ABS"

      # Esperar a que la VM esté lista (máximo 10 minutos)
      echo "⏳ Esperando que la VM esté lista..."
      timeout=600
      elapsed=0

      while [ $elapsed -lt $timeout ]; do
        STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
          --zone="$ZONE" \
          --project="$PROJECT" \
          --format='get(status)' 2>/dev/null || echo "UNKNOWN")

        if [ "$STATUS" = "RUNNING" ]; then
          echo "✅ VM está en estado RUNNING"
          break
        fi

        sleep 5
        elapsed=$((elapsed + 5))
      done

      if [ "$STATUS" != "RUNNING" ]; then
        echo "❌ Error: VM no está lista después de $timeout segundos"
        echo "   Estado final: $STATUS"
        exit 1
      fi

      # Crear directorio destino en la VM
      echo "📁 Creando directorio destino..."
      if ! gcloud compute ssh "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT" \
        --command="sudo mkdir -p '$DEST_DIR' && sudo chown $USER:$USER '$DEST_DIR'" \
        --tunnel-through-iap \
        --quiet 2>&1; then
        echo "⚠️  Error: No se pudo crear el directorio vía SSH"
        echo "   Verifica que la VM tenga el tag 'allow-iap-ssh' y que IAP esté habilitado"
        exit 1
      fi

      # Preparar directorio temporal
      TEMP_DIR="/tmp/config-$$"
      CONFIG_DIR_NAME=$(basename "$SRC_DIR_ABS")

      if ! gcloud compute ssh "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT" \
        --command="mkdir -p '$TEMP_DIR'" \
        --tunnel-through-iap \
        --quiet 2>&1; then
        echo "❌ Error: No se pudo crear directorio temporal"
        exit 1
      fi

      # Copiar archivos recursivamente
      echo "📤 Copiando archivos..."
      if ! gcloud compute scp \
        --recurse \
        --zone="$ZONE" \
        --project="$PROJECT" \
        --tunnel-through-iap \
        "$SRC_DIR_ABS" \
        "$USER@$INSTANCE_NAME:$TEMP_DIR/" 2>&1; then
        echo "❌ Error: No se pudieron copiar archivos"
        exit 1
      fi

      # Mover archivos al destino final con permisos correctos
      echo "📦 Moviendo archivos al destino final..."
      if ! gcloud compute ssh "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT" \
        --command="sudo cp -r '$TEMP_DIR/$CONFIG_DIR_NAME'/* '$DEST_DIR/' && sudo chown -R $USER:$USER '$DEST_DIR' && sudo rm -rf '$TEMP_DIR'" \
        --tunnel-through-iap \
        --quiet 2>&1; then
        echo "❌ Error: No se pudieron mover archivos al destino final"
        exit 1
      fi

      # Dar permisos de ejecución a scripts .sh
      echo "🔐 Configurando permisos de ejecución..."
      gcloud compute ssh "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT" \
        --command="sudo find '$DEST_DIR' -type f -name '*.sh' -exec chmod +x {} \\;" \
        --tunnel-through-iap \
        --quiet 2>&1 || true

      echo "✅ Scripts de despliegue copiados exitosamente"
    EOT
  }

  # Asegurar que la VM esté creada antes de ejecutar el provisioner
  depends_on = [module.vm_base]
}
