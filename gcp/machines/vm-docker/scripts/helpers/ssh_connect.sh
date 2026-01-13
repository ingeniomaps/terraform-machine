#!/bin/bash
# Script para conectar por SSH con prioridad: .pem > .json > IAP > OS Login > IP pública
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/get_terraform_values.sh"

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
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
CREDENTIALS_JSON=$(get_credentials_json)

if [ -z "$INSTANCE_NAME" ] || [ -z "$INSTANCE_ZONE" ] || [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}Error: No se puede obtener información de la VM${NC}" >&2
  echo -e "${YELLOW}Ejecuta 'terraform apply' primero${NC}" >&2
  exit 1
fi

echo -e "${BLUE}Intentando conexión SSH con prioridad: .pem > .json > IAP > OS Login > IP pública${NC}"

# Prioridad 1: Usar .pem si existe
if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
  echo -e "${GREEN}Usando clave .pem: $SSH_KEY_PATH${NC}"
  if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ] && [ -n "$EXTERNAL_IP" ]; then
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$EXTERNAL_IP"
  else
    echo -e "${YELLOW}No hay IP pública, intentando con IAP...${NC}"
    gcloud compute ssh "$SSH_USER@$INSTANCE_NAME" \
      --zone="$INSTANCE_ZONE" \
      --project="$PROJECT_ID" \
      --tunnel-through-iap \
      --ssh-key-file="$SSH_KEY_PATH" \
      --ssh-flag="-o StrictHostKeyChecking=no"
  fi
# Prioridad 2: Usar .json si existe
elif [ -n "$CREDENTIALS_JSON" ] && [ -f "$CREDENTIALS_JSON" ]; then
  echo -e "${GREEN}Usando credenciales JSON: $CREDENTIALS_JSON${NC}"
  export GOOGLE_APPLICATION_CREDENTIALS="$CREDENTIALS_JSON"
  if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ] && [ -n "$EXTERNAL_IP" ]; then
    gcloud compute ssh "$SSH_USER@$INSTANCE_NAME" \
      --zone="$INSTANCE_ZONE" \
      --project="$PROJECT_ID" \
      --ssh-flag="-o StrictHostKeyChecking=no"
  else
    gcloud compute ssh "$SSH_USER@$INSTANCE_NAME" \
      --zone="$INSTANCE_ZONE" \
      --project="$PROJECT_ID" \
      --tunnel-through-iap \
      --ssh-flag="-o StrictHostKeyChecking=no"
  fi
# Prioridad 3: Usar script ssh.sh (IAP > OS Login > IP pública)
else
  echo -e "${YELLOW}No se encontró .pem ni .json, usando script ssh.sh...${NC}"
  "${SCRIPT_DIR}/../ssh.sh"
fi
