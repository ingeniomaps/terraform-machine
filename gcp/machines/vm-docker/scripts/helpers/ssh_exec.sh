#!/bin/bash
# Script para ejecutar comando en la VM
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/get_terraform_values.sh"

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

SSH_USER="${SSH_USER:-ubuntu}"

if [ -z "${1:-}" ]; then
  echo -e "${RED}Error: Debes especificar un comando${NC}" >&2
  exit 1
fi

CMD="$1"

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
  exit 1
fi

echo -e "${GREEN}Ejecutando: $CMD${NC}"

# Determinar método de conexión SSH (prioridad: .pem > .json > IAP)
# Si hay .pem e IP pública, usar ssh directamente (evita que gcloud cree claves)
if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ] && \
   [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ] && [ -n "$EXTERNAL_IP" ]; then
  echo -e "${GREEN}Usando clave .pem con IP pública: $SSH_KEY_PATH${NC}"
  # Ejecutar ssh directamente - usar ConnectTimeout para detectar errores de conexión
  # No usar timeout general porque algunos comandos son interactivos (ej: tail -f)
  ssh -i "$SSH_KEY_PATH" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 \
    "$SSH_USER@$EXTERNAL_IP" \
    "$CMD" 2>&1
  SSH_EXIT_CODE=$?

  # Si fue interrumpido por el usuario (SIGINT = 130) o exit exitoso (0), salir directamente
  if [ $SSH_EXIT_CODE -eq 0 ] || [ $SSH_EXIT_CODE -eq 130 ]; then
    exit $SSH_EXIT_CODE
  fi

  # Solo intentar IAP si fue un error de conexión (no interrupción del usuario)
  echo -e "${YELLOW}SSH directo falló, intentando con IAP...${NC}" >&2
fi

# Si hay .pem pero no IP pública, o si ssh directo falló, usar IAP
# NO usar --ssh-key-file para evitar que gcloud intente crear la clave pública
# Usar IAP con la sesión de gcloud activa (no especificar clave)
if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
  echo -e "${GREEN}Usando IAP (gcloud usará la sesión activa)${NC}"
  SSH_OPTS="--tunnel-through-iap"
elif [ -n "$CREDENTIALS_JSON" ] && [ -f "$CREDENTIALS_JSON" ]; then
  echo -e "${GREEN}Usando credenciales JSON: $CREDENTIALS_JSON${NC}"
  export GOOGLE_APPLICATION_CREDENTIALS="$CREDENTIALS_JSON"
  SSH_OPTS="--tunnel-through-iap"
else
  echo -e "${YELLOW}No se encontró .pem ni .json, usando IAP${NC}"
  SSH_OPTS="--tunnel-through-iap"
fi

# Capturar la salida completa del comando SSH para mostrar el error real
SSH_OUTPUT=$(gcloud compute ssh "$SSH_USER@$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  $SSH_OPTS \
  --command="$CMD" 2>&1)
SSH_EXIT_CODE=$?

if [ $SSH_EXIT_CODE -ne 0 ]; then
  echo -e "${RED}Error al ejecutar comando en la VM:${NC}" >&2
  echo "$SSH_OUTPUT" >&2 # Mostrar el error real
  exit $SSH_EXIT_CODE
fi
echo "$SSH_OUTPUT" # Mostrar la salida si es exitosa
