#!/bin/bash
set -euo pipefail

# ============================================================================
# CONFIGURACIÓN: Usuario principal de la VM
# ============================================================================
# Cambiar este valor si el usuario principal de la VM es diferente
readonly MAIN_USER="${MAIN_USER:-ubuntu}"
readonly MAIN_USER_HOME="/home/${MAIN_USER}"

# Verificar que se ejecute como usuario principal
# Si no es el usuario principal, re-ejecutarse como él
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" != "$MAIN_USER" ]; then
  echo -e "\033[1;33mEjecutando como usuario $MAIN_USER (usuario actual: $CURRENT_USER)\033[0m" >&2
  # Re-ejecutar el script completo como usuario principal
  exec sudo -u "$MAIN_USER" "$0" "$@"
fi

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

usage() {
  echo "Usage: $0 <microservices_json>"
  exit 1
}

[ $# -eq 1 ] || usage

MICROSERVICES_JSON="$1"

[ -n "$MICROSERVICES_JSON" ] || {
  echo -e "${RED}Error: Microservices JSON not provided${NC}" >&2
  usage
}

# Verificar que podemos acceder al directorio home del usuario principal
if [ ! -w "$MAIN_USER_HOME" ]; then
  echo -e "${RED}Error: No se tienen permisos de escritura en $MAIN_USER_HOME${NC}" >&2
  echo -e "${RED}Usuario actual: $(whoami)${NC}" >&2
  exit 1
fi

cd "$MAIN_USER_HOME"

service_exists() {
  local name="$1"
  [ -d "$name" ] && return 0 || return 1
}

deploy_service() {
  local name="$1"
  local repo_url="$2"
  local branch="$3"
  local env_content_base64="$4"
  local env_file_name="$5"
  local launch_command="$6"

  echo -e "${BLUE}=== Verifying microservice: $name ===${NC}"

  if service_exists "$name"; then
    echo -e "${GREEN}$name already exists, skipping${NC}"
    return 0
  fi

  echo -e "${YELLOW}Deploying $name...${NC}"

  SERVICE_DIR="${MAIN_USER_HOME}/$name"

  if ! git clone "$repo_url" -b "$branch" --depth=1 "$SERVICE_DIR" 2>&1; then
    echo -e "${RED}Error: Could not clone $name${NC}" >&2
    return 1
  fi

  cd "$SERVICE_DIR"
  git config --global --add safe.directory "$SERVICE_DIR" 2>/dev/null || true

  if [ -n "$env_content_base64" ]; then
    env_content_decoded=$(echo "$env_content_base64" | base64 -d)
    # Usar env_file_name si está especificado, sino usar .env por defecto
    env_file_name="${env_file_name:-.env}"
    printf '%b' "$env_content_decoded" > "$env_file_name"
    echo -e "${GREEN}$env_file_name file created${NC}"
  else
    echo -e "${YELLOW}Warning: No .env content provided${NC}"
  fi

  # Decodificar launch_command
  launch_command_valid=false
  launch_command_decoded=""

  if [ -n "$launch_command" ] && [ "$launch_command" != '""' ]; then
    launch_command_decoded=$(echo "$launch_command" | base64 -d 2>/dev/null || echo "")
    launch_command_decoded=$(echo "$launch_command_decoded" | xargs)
    [ -n "$launch_command_decoded" ] && [ "$launch_command_decoded" != "null" ] && launch_command_valid=true
  fi

  # Lanzar microservicio
  if [ "$launch_command_valid" = "true" ]; then
    echo -e "${BLUE}Executing custom launch command...${NC}"
    eval "$launch_command_decoded"
  elif [ -f "installer.sh" ]; then
    echo -e "${BLUE}Executing installer.sh...${NC}"
    bash installer.sh
  elif [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    echo -e "${BLUE}Starting docker-compose...${NC}"
    docker-compose up -d
  else
    echo -e "${YELLOW}No launch method found. Service cloned but not started.${NC}"
  fi

  cd "$MAIN_USER_HOME"
  echo -e "${GREEN}$name deployed successfully${NC}"
  return 0
}

# Procesar JSON usando python3
if ! command -v python3 &> /dev/null; then
  echo -e "${RED}Error: python3 not available${NC}" >&2
  exit 1
fi

PYTHON_SCRIPT_FILE="/tmp/process_microservices_$$.py"
cat > "$PYTHON_SCRIPT_FILE" <<'PYTHON_EOF'
import json
import sys
import base64
import shlex

try:
    services = json.load(sys.stdin)
    if not isinstance(services, list):
        print('Error: JSON must be a list', file=sys.stderr)
        sys.exit(1)

    for service in services:
        name = service.get('name', '')
        repo_url = service.get('repo_url', '')
        branch = service.get('branch', 'main')
        env_file = service.get('env_file', '')
        env_file_name = service.get('env_file_name', '.env')
        launch_command = service.get('launch_command')

        if not name or not repo_url:
            print(f'Warning: Invalid service (missing name or repo_url)', file=sys.stderr)
            continue

        env_content_b64 = base64.b64encode(env_file.encode('utf-8')).decode('utf-8')

        if launch_command and str(launch_command).strip():
            launch_command_b64 = base64.b64encode(str(launch_command).encode('utf-8')).decode('utf-8')
        else:
            launch_command_b64 = ''

        print(f'deploy_service {shlex.quote(name)} {shlex.quote(repo_url)} {shlex.quote(branch)} {shlex.quote(env_content_b64)} {shlex.quote(env_file_name)} {shlex.quote(launch_command_b64)}')
except json.JSONDecodeError as e:
    print(f'Error: Invalid JSON: {e}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

echo "$MICROSERVICES_JSON" | python3 "$PYTHON_SCRIPT_FILE" | while IFS= read -r line; do
  eval "$line"
done

rm -f "$PYTHON_SCRIPT_FILE"

echo -e "${GREEN}Microservices update completed${NC}"
