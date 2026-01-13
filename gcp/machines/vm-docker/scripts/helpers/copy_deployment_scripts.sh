#!/bin/bash
# Script para copiar scripts de despliegue personalizados a la VM
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/get_terraform_values.sh"

# Colores
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

# Obtener valores
cd "$TERRAFORM_DIR"
INSTANCE_NAME=$(get_instance_name)
INSTANCE_ZONE=$(get_instance_zone)
PROJECT_ID=$(get_project_id)

if [ -z "$INSTANCE_NAME" ] || [ -z "$INSTANCE_ZONE" ] || [ -z "$PROJECT_ID" ]; then
  exit 1
fi

DEPLOYMENT_SCRIPTS=$(grep '^deployment_scripts' terraform.tfvars 2>/dev/null | \
  sed 's/.*=.*"\(.*\)".*/\1/' | head -1 || echo "")

if [ -z "$DEPLOYMENT_SCRIPTS" ] || [ ! -d "$DEPLOYMENT_SCRIPTS" ]; then
  echo -e "${YELLOW}No hay scripts de despliegue configurados (variable deployment_scripts)${NC}"
  exit 0
fi

echo -e "${GREEN}Copiando scripts de despliegue...${NC}"
terraform output -json copy_deployment_scripts_info 2>/dev/null | jq -r \
  '"./modules/vm-docker/scripts/copy_deployment_scripts.sh " + \
  .instance_name + " " + \
  .zone + " " + \
  .project_id + " " + \
  .destination + " " + \
  .source + " " + \
  .user' | bash || \
  echo -e "${YELLOW}No se pudo copiar scripts (requiere gcloud y tag allow-iap-ssh)${NC}"
