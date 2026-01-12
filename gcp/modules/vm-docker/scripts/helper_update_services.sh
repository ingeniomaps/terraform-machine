#!/bin/bash
# ============================================================================
# HELPER SCRIPT: Actualización Manual de Microservicios
# ============================================================================
# Este script ayuda a actualizar microservicios manualmente desde dentro de la VM
# Copiar a /opt/scripts/helper_update_services.sh en la VM
# ============================================================================

set -e

# ============================================================================
# CONFIGURACIÓN: Usuario principal de la VM
# ============================================================================
# Cambiar este valor si el usuario principal de la VM es diferente
readonly MAIN_USER="${MAIN_USER:-ubuntu}"
readonly MAIN_USER_HOME="/home/${MAIN_USER}"

SCRIPT_DIR="/opt/scripts"
UPDATE_SCRIPT="$SCRIPT_DIR/update_microservices.sh"
HELPER_SCRIPT="$SCRIPT_DIR/helper_update_services.sh"

# Colores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Función para mostrar ayuda
show_help() {
  cat <<EOF
${BLUE}Helper para Actualización Manual de Microservicios${NC}

Uso:
  $0 [comando] [opciones]

Comandos:
  update-from-metadata    Actualizar usando configuración desde metadata de la VM
  update-one <nombre>     Actualizar un microservicio específico (git pull + rebuild)
  update-all              Actualizar TODOS los microservicios (git pull + rebuild)
  redeploy <nombre>       Re-desplegar un microservicio desde cero
  status                  Ver estado de todos los microservicios
  list                    Listar todos los microservicios desplegados
  logs <nombre>           Ver logs de un microservicio específico

Ejemplos:
  $0 update-from-metadata
  $0 update-one gateway
  $0 update-all
  $0 redeploy api-service
  $0 status
  $0 logs gateway

EOF
}

# Función para ejecutar como usuario principal si es necesario
run_as_main_user() {
  local current_user
  current_user=$(whoami)

  if [ "$current_user" = "$MAIN_USER" ]; then
    # Ya somos el usuario principal, ejecutar directamente
    "$@"
  else
    # Ejecutar como usuario principal usando sudo
    # Los scripts que se ejecutan ya tienen sus propias definiciones de colores
    echo -e "${YELLOW}Ejecutando como usuario $MAIN_USER (usuario actual: $current_user)${NC}"
    sudo -u "$MAIN_USER" "$@"
  fi
}

# Función para actualizar desde metadata
update_from_metadata() {
  echo -e "${BLUE}Actualizando microservicios desde metadata...${NC}"

  # Obtener JSON desde metadata (separar el pipe del if para evitar errores de sintaxis)
  METADATA_RAW=$(curl -s -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/instance/attributes/microservices_json 2>/dev/null)

  if [ -z "$METADATA_RAW" ]; then
    echo -e "${RED}Error: No se pudo obtener metadata de microservicios${NC}"
    echo "   Verifica que la VM tenga metadata 'microservices_json' configurado"
    return 1
  fi

  MICROSERVICES_JSON=$(echo "$METADATA_RAW" | base64 -d 2>/dev/null)

  if [ -z "$MICROSERVICES_JSON" ]; then
    echo -e "${YELLOW}No hay microservicios configurados en metadata o error al decodificar${NC}"
    return 0
  fi

  # Ejecutar script de actualización
  if [ ! -f "$UPDATE_SCRIPT" ]; then
    echo -e "${RED}Error: Script de actualización no encontrado en $UPDATE_SCRIPT${NC}"
    return 1
  fi

  # Ejecutar como usuario principal para tener permisos en el directorio home
  run_as_main_user bash "$UPDATE_SCRIPT" "$MICROSERVICES_JSON"
}

# Función para actualizar un microservicio específico
update_one() {
  local service_name="$1"

  if [ -z "$service_name" ]; then
    echo -e "${RED}Error: Debes especificar el nombre del microservicio${NC}"
    echo "   Uso: $0 update-one <nombre>"
    return 1
  fi

  local service_dir="${MAIN_USER_HOME}/$service_name"

  if [ ! -d "$service_dir" ]; then
    echo -e "${RED}Error: Microservicio '$service_name' no encontrado en $service_dir${NC}"
    return 1
  fi

  echo -e "${BLUE}Actualizando: $service_name${NC}"
  echo "=========================================="

  # Ejecutar como usuario principal para tener permisos
  run_as_main_user bash -c "
    cd '$service_dir'

    # Configurar Git para permitir este directorio (evitar \"dubious ownership\")
    git config --global --add safe.directory '$service_dir' 2>/dev/null || true

    # Obtener branch actual
    current_branch=\$(git branch --show-current 2>/dev/null || echo 'main')
    echo \"Branch actual: \$current_branch\"

    # Actualizar código
    echo \"Actualizando código desde el repositorio...\"
    if git pull origin \"\$current_branch\"; then
      echo -e \"\${GREEN}Código actualizado\${NC}\"
    else
      echo -e \"\${RED}Error al actualizar código\${NC}\"
      exit 1
    fi

    # Reconstruir si tiene docker-compose
    if [ -f \"docker-compose.yml\" ] || [ -f \"docker-compose.yaml\" ]; then
      echo \"Reconstruyendo contenedores...\"
      docker-compose down
      docker-compose up -d --build
      echo -e \"\${GREEN}$service_name actualizado y reiniciado\${NC}\"
    else
      echo -e \"\${YELLOW}No se encontró docker-compose.yml, solo se actualizó el código\${NC}\"
    fi
  "
}

# Función para actualizar todos los microservicios
update_all() {
  echo -e "${BLUE}Actualizando TODOS los microservicios...${NC}"
  echo ""

  # Ejecutar como usuario principal para tener permisos
  run_as_main_user bash -c "
    cd "$MAIN_USER_HOME"

    updated=0
    failed=0
    skipped=0

    # Iterar sobre cada directorio
    for service_dir in */; do
      service_name=\"\${service_dir%/}\"

      # Saltar directorios que no son repositorios git
      if [ ! -d \"\$service_dir/.git\" ]; then
        continue
      fi

      echo \"==========================================\"
      echo -e \"\${BLUE}Procesando: \$service_name\${NC}\"
      echo \"==========================================\"

      cd \"\$service_dir\"

      # Configurar Git para permitir este directorio (evitar \"dubious ownership\")
      git config --global --add safe.directory \"\$(pwd)\" 2>/dev/null || true

      # Obtener branch actual
      current_branch=\$(git branch --show-current 2>/dev/null || echo '')
      if [ -n \"\$current_branch\" ]; then
        echo \"Branch: \$current_branch\"
      else
        echo -e \"\${YELLOW}Saltando \$service_name (no es un repo git válido)\${NC}\"
        skipped=\$((skipped + 1))
        cd ..
        continue
      fi

      # Actualizar código
      if git pull origin \"\$current_branch\" 2>&1; then
        # Reconstruir si tiene docker-compose
        if [ -f \"docker-compose.yml\" ] || [ -f \"docker-compose.yaml\" ]; then
          docker-compose down
          docker-compose up -d --build
          echo -e \"\${GREEN}\$service_name actualizado\${NC}\"
          updated=\$((updated + 1))
        else
          echo -e \"\${GREEN}\$service_name actualizado (sin docker-compose)\${NC}\"
          updated=\$((updated + 1))
        fi
      else
        echo -e \"\${RED}Error actualizando \$service_name\${NC}\"
        failed=\$((failed + 1))
      fi

      cd ..
      echo \"\"
    done

    echo \"==========================================\"
    echo -e \"\${GREEN}Actualización completada:\${NC}\"
    echo \"  Actualizados: \$updated\"
    echo \"  Fallidos: \$failed\"
    echo \"   Omitidos: \$skipped\"
    echo \"==========================================\"
  "
}

# Función para re-desplegar un microservicio
redeploy() {
  local service_name="$1"

  if [ -z "$service_name" ]; then
    echo -e "${RED}Error: Debes especificar el nombre del microservicio${NC}"
    echo "   Uso: $0 redeploy <nombre>"
    return 1
  fi

  local service_dir="$MAIN_USER_HOME/$service_name"

  if [ ! -d "$service_dir" ]; then
    echo -e "${RED}Error: Microservicio '$service_name' no encontrado${NC}"
    return 1
  fi

  echo -e "${YELLOW}Re-desplegando $service_name desde cero...${NC}"
  echo "Esto eliminará el directorio actual y lo volverá a clonar"
  read -p "¿Continuar? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelado"
    return 0
  fi

  # Ejecutar como usuario principal para tener permisos
  run_as_main_user bash -c "
    cd "$MAIN_USER_HOME"

    # Detener contenedores
    if [ -f '$service_dir/docker-compose.yml' ] || [ -f '$service_dir/docker-compose.yaml' ]; then
      echo 'Deteniendo contenedores...'
      cd '$service_dir'
      docker-compose down
      cd "$MAIN_USER_HOME"
    fi

    # Eliminar directorio
    echo 'Eliminando directorio...'
    rm -rf '$service_dir'
  "

  # Actualizar desde metadata
  echo "Re-desplegando desde metadata..."
  update_from_metadata
}

# Función para ver estado
status() {
  echo -e "${BLUE}Estado de Microservicios${NC}"
  echo "=========================================="
  echo ""

  # Ejecutar como usuario principal para tener permisos
  run_as_main_user bash -c "
    cd "$MAIN_USER_HOME"

    echo -e \"\${BLUE}Contenedores Docker:\${NC}\"
    docker ps --format \"table {{.Names}}\t{{.Status}}\t{{.Ports}}\"
    echo \"\"

    echo -e \"\${BLUE}Microservicios Desplegados:\${NC}\"
    for service_dir in */; do
      service_name=\"\${service_dir%/}\"
      service_path=\"$MAIN_USER_HOME/\$service_name\"

      if [ -d \"\$service_path/.git\" ]; then
        cd \"\$service_path\"
        current_branch=\$(git branch --show-current 2>/dev/null || echo \"unknown\")
        last_commit=\$(git log -1 --format=\"%h - %s\" 2>/dev/null || echo \"unknown\")

        # Verificar si tiene docker-compose y contenedores corriendo
        if [ -f \"docker-compose.yml\" ] || [ -f \"docker-compose.yaml\" ]; then
          PYTHON_CHECK_CMD=\"import sys, json; \" \
            \"data=json.load(sys.stdin); \" \
            \"print('running' if any(c['State']=='running' for c in data) \" \
            \"else 'stopped')\"
          container_status=\$(docker-compose ps --format json 2>/dev/null | \
            python3 -c \"\$PYTHON_CHECK_CMD\" 2>/dev/null || echo \"unknown\")
          echo -e \"  \${GREEN}✓\${NC} \$service_name\"
          echo \"      Branch: \$current_branch\"
          echo \"      Último commit: \$last_commit\"
          echo \"      Estado contenedores: \$container_status\"
        else
          echo -e \"  \${YELLOW}○\${NC} \$service_name\"
          echo \"      Branch: \$current_branch\"
          echo \"      Último commit: \$last_commit\"
          echo \"      (sin docker-compose)\"
        fi

        cd "$MAIN_USER_HOME"
        echo \"\"
      fi
    done
  "
}

# Función para listar microservicios
list() {
  echo -e "${BLUE}Microservicios Desplegados:${NC}"
  echo ""

  # Ejecutar como usuario principal para tener permisos
  run_as_main_user bash -c "
    cd "$MAIN_USER_HOME"
    for service_dir in */; do
      service_name=\"\${service_dir%/}\"
      if [ -d \"\$service_dir/.git\" ]; then
        echo \"  • \$service_name\"
      fi
    done
  "
}

# Función para ver logs
logs() {
  local service_name="$1"

  if [ -z "$service_name" ]; then
    echo -e "${RED}Error: Debes especificar el nombre del microservicio${NC}"
    echo "   Uso: $0 logs <nombre>"
    return 1
  fi

  local service_dir="$MAIN_USER_HOME/$service_name"

  if [ ! -d "$service_dir" ]; then
    echo -e "${RED}Error: Microservicio '$service_name' no encontrado${NC}"
    return 1
  fi

  # Ejecutar como usuario principal para tener permisos
  run_as_main_user bash -c "
    cd '$service_dir'

    if [ -f \"docker-compose.yml\" ] || [ -f \"docker-compose.yaml\" ]; then
      echo -e \"\${BLUE}Logs de $service_name\${NC}\"
      echo \"Presiona Ctrl+C para salir\"
      echo \"\"
      docker-compose logs -f --tail=50
    else
      echo -e \"\${YELLOW}Este microservicio no tiene docker-compose.yml\${NC}\"
    fi
  "
}

# Main
# Si no se proporciona ningún argumento, mostrar ayuda
if [ $# -eq 0 ]; then
  show_help
  exit 0
fi

case "${1:-}" in
  update-from-metadata)
    update_from_metadata
    ;;
  update-one)
    update_one "$2"
    ;;
  update-all)
    update_all
    ;;
  redeploy)
    redeploy "$2"
    ;;
  status)
    status
    ;;
  list)
    list
    ;;
  logs)
    logs "$2"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    echo -e "${RED}Comando desconocido: $1${NC}"
    echo ""
    show_help
    exit 1
    ;;
esac
