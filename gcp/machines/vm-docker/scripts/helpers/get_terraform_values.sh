#!/bin/bash
# Script helper para obtener valores de Terraform
set -euo pipefail

# Colores (solo si no están definidos)
: "${RED:='\033[0;31m'}"
: "${GREEN:='\033[0;32m'}"
: "${YELLOW:='\033[1;33m'}"
: "${BLUE:='\033[0;34m'}"
: "${NC:='\033[0m'}"

# SCRIPT_DIR debe ser definido por el script que hace source de este archivo
# Si no está definido, calcularlo desde este script
if [ -z "${SCRIPT_DIR:-}" ]; then
  readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
# scripts/helpers -> scripts -> . (raíz donde está terraform.tfvars)
readonly TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "$TERRAFORM_DIR"

# Funciones para obtener valores
get_instance_name() {
  terraform output -raw instance_name 2>/dev/null || echo ""
}

get_instance_zone() {
  terraform output -raw instance_zone 2>/dev/null || echo ""
}

get_project_id() {
  terraform output -raw project_id 2>/dev/null || \
    grep '^project_id' terraform.tfvars 2>/dev/null | \
    sed 's/.*"\(.*\)".*/\1/' | head -1 || echo ""
}

get_external_ip() {
  terraform output -raw external_ip 2>/dev/null || echo ""
}

get_ssh_key_path() {
  # Primero intentar obtener desde Terraform output (si existe)
  local terraform_path
  terraform_path=$(terraform output -raw ssh_private_key_path 2>/dev/null || echo "")

  # Si existe el archivo desde Terraform, usarlo
  if [ -n "$terraform_path" ] && [ -f "$terraform_path" ]; then
    echo "$terraform_path"
    return 0
  fi

  # Si no, buscar manualmente en keys/ (sin crear nueva)
  local instance_name
  instance_name=$(get_instance_name)
  if [ -n "$instance_name" ]; then
    local key_path="${TERRAFORM_DIR}/keys/${instance_name}.pem"
    if [ -f "$key_path" ]; then
      echo "$key_path"
      return 0
    fi
  fi

  # Buscar cualquier .pem en keys/
  if [ -d "${TERRAFORM_DIR}/keys" ]; then
    local found_key
    found_key=$(find "${TERRAFORM_DIR}/keys" -maxdepth 1 -name "*.pem" -type f 2>/dev/null | head -1)
    if [ -n "$found_key" ]; then
      echo "$found_key"
      return 0
    fi
  fi

  # No se encontró ninguna clave, retornar vacío (NO crear nueva)
  echo ""
}

get_credentials_json() {
  if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] && \
     [ -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]; then
    echo "${GOOGLE_APPLICATION_CREDENTIALS}"
  elif [ -d "../keys" ] && \
       [ -n "$(find ../keys -maxdepth 1 -name '*.json' -type f 2>/dev/null | head -1)" ]; then
    find ../keys -maxdepth 1 -name '*.json' -type f 2>/dev/null | head -1
  fi || echo ""
}

# Si se llama directamente, exportar valores
if [ "${1:-}" = "export" ]; then
  INSTANCE_NAME=$(get_instance_name)
  INSTANCE_ZONE=$(get_instance_zone)
  PROJECT_ID=$(get_project_id)
  EXTERNAL_IP=$(get_external_ip)
  SSH_KEY_PATH=$(get_ssh_key_path)
  CREDENTIALS_JSON=$(get_credentials_json)

  export INSTANCE_NAME INSTANCE_ZONE PROJECT_ID EXTERNAL_IP SSH_KEY_PATH CREDENTIALS_JSON

  if [ -z "$INSTANCE_NAME" ] || [ -z "$INSTANCE_ZONE" ] || [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No se puede obtener información de la VM${NC}" >&2
    echo -e "${YELLOW}Ejecuta 'terraform apply' primero${NC}" >&2
    exit 1
  fi
fi
