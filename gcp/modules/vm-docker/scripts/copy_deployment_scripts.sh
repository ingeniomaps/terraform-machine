#!/bin/bash
set -euo pipefail

# Script para copiar scripts y archivos de despliegue a la VM usando gcloud con IAP
# Útil para archivos grandes que exceden el límite de metadata (256KB) o directorios completos

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

usage() {
  echo "Usage: $0 <instance_name> <zone> <project_id> <destination_dir> <source_dir> <user>"
  exit 1
}

[ $# -eq 6 ] || usage

INSTANCE_NAME="$1"
ZONE="$2"
PROJECT="$3"
DEST_DIR="$4"
SRC_DIR="$5"
USER="$6"

echo -e "${GREEN}Copying deployment scripts to VM...${NC}"
echo "  Instance: $INSTANCE_NAME"
echo "  Zone: $ZONE"
echo "  Source: $SRC_DIR"
echo "  Destination: $DEST_DIR"

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

if [ ! -d "$SRC_DIR_ABS" ]; then
  echo -e "${RED}Error: Invalid directory: $SRC_DIR${NC}" >&2
  exit 1
fi

echo -e "${GREEN}Source directory: $SRC_DIR_ABS${NC}"

# Esperar a que la VM esté lista (máximo 10 minutos)
echo -e "${YELLOW}Waiting for VM to be ready...${NC}"
timeout=600
elapsed=0
STATUS="UNKNOWN"

while [ $elapsed -lt $timeout ]; do
  STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT" \
    --format='get(status)' 2>/dev/null || echo "UNKNOWN")

  [ "$STATUS" = "RUNNING" ] && break

  sleep 5
  elapsed=$((elapsed + 5))
done

if [ "$STATUS" != "RUNNING" ]; then
  echo -e "${RED}Error: VM not ready after ${timeout}s (status: $STATUS)${NC}" >&2
  exit 1
fi

# Crear directorio destino
echo "Creating destination directory..."
if ! gcloud compute ssh "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --project="$PROJECT" \
  --command="sudo mkdir -p '$DEST_DIR' && sudo chown $USER:$USER '$DEST_DIR'" \
  --tunnel-through-iap \
  --quiet 2>&1; then
  echo -e "${RED}Error: Could not create directory via SSH${NC}" >&2
  echo "  Verify VM has tag 'allow-iap-ssh' and IAP is enabled" >&2
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
  echo -e "${RED}Error: Could not create temp directory${NC}" >&2
  exit 1
fi

# Copiar archivos recursivamente
echo "Copying files..."
if ! gcloud compute scp \
  --recurse \
  --zone="$ZONE" \
  --project="$PROJECT" \
  --tunnel-through-iap \
  "$SRC_DIR_ABS" \
  "$USER@$INSTANCE_NAME:$TEMP_DIR/" 2>&1; then
  echo -e "${RED}Error: Could not copy files${NC}" >&2
  exit 1
fi

# Mover archivos al destino final
echo "Moving files to destination..."
MOVE_CMD="sudo cp -r '$TEMP_DIR/$CONFIG_DIR_NAME'/* '$DEST_DIR/' && " \
  "sudo chown -R $USER:$USER '$DEST_DIR' && " \
  "sudo rm -rf '$TEMP_DIR'"
if ! gcloud compute ssh "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --project="$PROJECT" \
  --command="$MOVE_CMD" \
  --tunnel-through-iap \
  --quiet 2>&1; then
  echo -e "${RED}Error: Could not move files to destination${NC}" >&2
  exit 1
fi

# Dar permisos de ejecución a scripts .sh
echo "Setting execute permissions..."
gcloud compute ssh "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --project="$PROJECT" \
  --command="sudo find '$DEST_DIR' -type f -name '*.sh' -exec chmod +x {} \\;" \
  --tunnel-through-iap \
  --quiet 2>&1 || true

echo -e "${GREEN}Deployment scripts copied successfully${NC}"
