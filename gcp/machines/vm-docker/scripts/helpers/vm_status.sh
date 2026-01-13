#!/bin/bash
# Script para mostrar estado de la VM y microservicios
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
EXTERNAL_IP=$(get_external_ip)

if [ -z "$INSTANCE_NAME" ] || [ -z "$INSTANCE_ZONE" ] || [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}Error: No se puede obtener información de la VM${NC}" >&2
  echo -e "${YELLOW}Ejecuta 'terraform apply' primero${NC}" >&2
  exit 1
fi

echo -e "${GREEN}Estado de la VM:${NC}"
gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  --format="table(name,status,zone,machineType)" 2>/dev/null || \
  echo -e "${RED}Error al obtener estado${NC}"

echo ""
echo -e "${GREEN}IPs:${NC}"
echo "  Externa: $EXTERNAL_IP"
INTERNAL_IP=$(terraform output -raw internal_ip 2>/dev/null || echo "N/A")
echo "  Interna: $INTERNAL_IP"
echo ""
echo -e "${BLUE}Para ver estado de microservicios, ejecuta: make microservices-status${NC}"
