#!/bin/bash
# Script para ejecutar comandos post-deploy
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/get_terraform_values.sh"

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Obtener valores
cd "$TERRAFORM_DIR"
INSTANCE_NAME=$(get_instance_name)
INSTANCE_ZONE=$(get_instance_zone)
PROJECT_ID=$(get_project_id)

if [ -z "$INSTANCE_NAME" ] || [ -z "$INSTANCE_ZONE" ] || [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}Error: No se puede obtener información de la VM${NC}" >&2
  echo -e "${YELLOW}Ejecuta 'terraform apply' primero${NC}" >&2
  exit 1
fi

echo -e "${BLUE}Verificando estado de la VM...${NC}"
STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  --format='get(status)' 2>/dev/null || echo "")

if [ "$STATUS" != "RUNNING" ]; then
  echo -e "${YELLOW}VM no está RUNNING, esperando...${NC}"
  gcloud compute instances wait "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --project="$PROJECT_ID" \
    --timeout=300 2>/dev/null || true
fi

echo -e "${GREEN}VM está RUNNING${NC}"
echo -e "${BLUE}Esperando a que la VM esté lista (30 segundos)...${NC}"
sleep 30

# Copiar scripts de despliegue si están configurados
"${SCRIPT_DIR}/copy_deployment_scripts.sh" 2>/dev/null || \
  echo -e "${YELLOW}No hay scripts de despliegue para copiar${NC}"

echo -e "${GREEN}Post-deploy completado${NC}"
