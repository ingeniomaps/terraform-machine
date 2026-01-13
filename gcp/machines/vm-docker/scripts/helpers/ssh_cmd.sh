#!/bin/bash
# Script para mostrar comando SSH sin ejecutar
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/get_terraform_values.sh"

# Colores
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

SSH_USER="${SSH_USER:-ubuntu}"

# Obtener valores
cd "$TERRAFORM_DIR"
INSTANCE_NAME=$(get_instance_name)
INSTANCE_ZONE=$(get_instance_zone)
PROJECT_ID=$(get_project_id)
EXTERNAL_IP=$(get_external_ip)
SSH_KEY_PATH=$(get_ssh_key_path)

if [ -z "$INSTANCE_NAME" ] || [ -z "$INSTANCE_ZONE" ] || [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}Error: No se puede obtener información de la VM${NC}" >&2
  exit 1
fi

echo -e "${BLUE}Comando SSH:${NC}"

if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
  if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ] && [ -n "$EXTERNAL_IP" ]; then
    echo "ssh -i $SSH_KEY_PATH $SSH_USER@$EXTERNAL_IP"
  else
    echo "gcloud compute ssh $SSH_USER@$INSTANCE_NAME \\"
    echo "  --zone=$INSTANCE_ZONE \\"
    echo "  --project=$PROJECT_ID \\"
    echo "  --tunnel-through-iap \\"
    echo "  --ssh-key-file=$SSH_KEY_PATH"
  fi
else
  terraform output ssh_command 2>/dev/null || {
    echo "gcloud compute ssh $SSH_USER@$INSTANCE_NAME \\"
    echo "  --zone=$INSTANCE_ZONE \\"
    echo "  --project=$PROJECT_ID \\"
    echo "  --tunnel-through-iap"
  }
fi
