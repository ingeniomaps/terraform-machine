#!/bin/bash
set -euo pipefail

# ============================================================================
# CONFIGURACIÓN: Usuario principal de la VM
# ============================================================================
# Cambiar este valor si el usuario principal de la VM es diferente
readonly MAIN_USER="$${MAIN_USER:-ubuntu}"
readonly MAIN_USER_HOME="/home/$${MAIN_USER}"

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

cd "$${MAIN_USER_HOME}"

service_exists() {
  local name="$1"
  [ -d "$name" ] && return 0 || return 1
}

deploy_service() {
  local name="$1"
  local repo_url="$2"
  local branch="$3"
  local env_content="$4"
  local env_file_name="$5"
  local launch_command="$6"

  [ -z "$env_file_name" ] && env_file_name=".env"

  echo -e "$$${BLUE}=== Verifying microservice: $name ===$$${NC}"

  if service_exists "$name"; then
    echo -e "$${GREEN}$name already exists, skipping$${NC}"
    return 0
  fi

  echo -e "$${YELLOW}Deploying $name...$${NC}"

  SERVICE_DIR="$${MAIN_USER_HOME}/$name"

  if ! git clone "$repo_url" -b "$branch" --depth=1 "$SERVICE_DIR" 2>&1; then
    echo -e "$${RED}Error: Could not clone $name$${NC}" >&2
    return 1
  fi

  cd "$SERVICE_DIR"
  git config --global --add safe.directory "$SERVICE_DIR" 2>/dev/null || true

  printf '%b' "$env_content" > "$env_file_name"
  echo -e "$${GREEN}$env_file_name file created$${NC}"

  # Validar launch_command
  launch_command_valid=false
  launch_command_clean=""
  launch_command=$(echo "$launch_command" | xargs)

  if [ -n "$launch_command" ] && \
     [ "$launch_command" != "null" ] && \
     [ "$launch_command" != '""' ] && \
     [ "$launch_command" != "''" ]; then
    launch_command_clean=$(printf '%b' "$launch_command" | \
      sed -e 's/^["'\'']*//' -e 's/["'\'']*$//' | xargs)
    if [ -n "$launch_command_clean" ] && \
       [ "$launch_command_clean" != "null" ] && \
       [ "$launch_command_clean" != '""' ]; then
      launch_command_valid=true
    fi
  fi

  # Lanzar el microservicio
  if [ "$launch_command_valid" = "true" ]; then
    echo -e "$${BLUE}Executing custom launch command...$${NC}"
    eval "$launch_command_clean"
  elif [ -f "installer.sh" ]; then
    echo -e "$${BLUE}Executing installer.sh...$${NC}"
    bash installer.sh
  elif [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    echo -e "$${BLUE}Starting docker-compose...$${NC}"
    docker-compose up -d
  else
    echo -e "$${YELLOW}No launch method found. Service cloned but not started.$${NC}"
  fi

  cd "$${MAIN_USER_HOME}"
  echo -e "$${GREEN}$name deployed successfully$${NC}"
  return 0
}

# Desplegar cada microservicio
%{ for service in microservices ~}
deploy_service "${service.name}" "${service.repo_url}" "${service.branch}" ${jsonencode(service.env_file)} "${service.env_file_name}" ${try(jsonencode(service.launch_command), jsonencode(""))}
%{ endfor ~}

echo -e "$${GREEN}Microservices deployment completed$${NC}"
