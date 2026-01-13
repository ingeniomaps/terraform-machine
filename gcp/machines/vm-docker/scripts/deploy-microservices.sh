#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Deploy de microservicios en VM existente (Terraform + IAP safe)
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly DEPLOY_SCRIPT_LOCAL="/tmp/deploy_microservices.sh"
readonly DEPLOY_SCRIPT_REMOTE="/tmp/deploy-microservices.sh"

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

ACTION=""
ONLY_SERVICES=""
FORCE_SERVICES=""

# ============================================================================
# HELP
# ============================================================================

show_help() {
  cat <<EOF
Uso: $0 [--apply | --apply-deploy | --deploy-only | --ssh]

Opciones:
  --apply           Solo terraform apply
  --apply-deploy    Terraform apply + deploy (RECOMENDADO)
  --deploy-only     Solo deploy (terraform ya aplicado)
  --ssh             Mostrar comando SSH para conectarse a la VM

Filtros:
  --only=a,b,c      Solo estos servicios
  --force=a,b       Forzar redeploy

EOF
}

# ============================================================================
# ARGUMENTOS
# ============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply|--apply-deploy|--deploy-only|--ssh)
      ACTION="$1"
      ;;
    --only=*)  ONLY_SERVICES="${1#*=}" ;;
    --only)    ONLY_SERVICES="${2:-}"; shift ;;
    --force=*) FORCE_SERVICES="${1#*=}" ;;
    --force)   FORCE_SERVICES="${2:-}"; shift ;;
    --help|-h) show_help; exit 0 ;;
    *) echo -e "${YELLOW}Argumento no reconocido: $1${NC}" >&2 ;;
  esac
  shift
done

# ============================================================================
# TERRAFORM / VM INFO
# ============================================================================

get_vm_info() {
  cd "${TERRAFORM_DIR}"

  INSTANCE_NAME="$(terraform output -raw instance_name 2>/dev/null || true)"
  INSTANCE_ZONE="$(terraform output -raw instance_zone 2>/dev/null || true)"
  PROJECT_ID="$(grep '^project_id' terraform.tfvars | sed 's/.*"\(.*\)".*/\1/' | head -1)"

  [[ -z "$INSTANCE_NAME" || -z "$INSTANCE_ZONE" ]] && {
    echo -e "${RED}Error: No se pudo obtener info de la VM (terraform output)${NC}" >&2
    exit 1
  }

  echo -e "${BLUE}VM: $INSTANCE_NAME | Zona: $INSTANCE_ZONE | Proyecto: $PROJECT_ID${NC}"
}

apply_terraform() {
  echo -e "${BLUE}Ejecutando terraform apply...${NC}"
  terraform apply -auto-approve
  echo -e "${GREEN}Terraform aplicado${NC}"
}

# ============================================================================
# SSH / IAP
# ============================================================================

detect_ssh_opts() {
  echo -e "${BLUE}Detectando método de conexión...${NC}"

  # Verificar IP pública (variable global para usar después)
  VM_IP="$(timeout 10 gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --project="$PROJECT_ID" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || echo "None")"

  # Verificar OS Login (variable global para usar después)
  OS_LOGIN_ENABLED="$(timeout 5 gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --project="$PROJECT_ID" \
    --format='value(metadata.items[enable-oslogin])' 2>/dev/null || echo "FALSE")"

  # Prioridad: IAP > IP pública > OS Login
  # 1. IAP (siempre disponible, más seguro)
  SSH_OPTS="--tunnel-through-iap"
  SSH_USER="ubuntu"
  echo -e "${GREEN}Prioridad: IAP (método preferido)${NC}"

  # 2. Si hay IP pública, también intentar ese método como alternativa
  if [[ -n "$VM_IP" && "$VM_IP" != "None" ]]; then
    echo -e "${BLUE}IP pública disponible: $VM_IP (fallback si IAP falla)${NC}"
  fi

  # 3. Verificar OS Login como último recurso
  if [[ "$OS_LOGIN_ENABLED" == "TRUE" ]]; then
    echo -e "${BLUE}OS Login habilitado (último recurso si otros fallan)${NC}"
  fi
}

check_vm_running() {
  echo -e "${BLUE}Verificando estado de la VM...${NC}"
  local status
  status="$(timeout 10 gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --project="$PROJECT_ID" \
    --format='get(status)' 2>/dev/null || echo "UNKNOWN")"

  if [[ "$status" == "UNKNOWN" ]]; then
    echo -e "${YELLOW}No se pudo verificar el estado (timeout o error)${NC}"
    echo -e "${YELLOW}Continuando de todas formas...${NC}"
    return 0
  fi

  if [[ "$status" != "RUNNING" ]]; then
    echo -e "${RED}Error: VM no está RUNNING (estado: $status)${NC}" >&2
    exit 1
  fi

  echo -e "${GREEN}VM está RUNNING${NC}"
}

# ============================================================================
# DEPLOY SCRIPT
# ============================================================================

generate_deploy_script() {
  echo -e "${BLUE}Generando script remoto...${NC}"

  cat > "$DEPLOY_SCRIPT_LOCAL" <<'EOF'
#!/usr/bin/env bash
set -e

# Asegurar que estamos en el directorio correcto y con permisos
if ! cd /home/ubuntu 2>/dev/null; then
  echo "No se pudo acceder a /home/ubuntu, intentando crear directorio..."
  sudo mkdir -p /home/ubuntu
  sudo chown ubuntu:ubuntu /home/ubuntu
  cd /home/ubuntu
fi

ONLY_SERVICES="__ONLY__"
FORCE_SERVICES="__FORCE__"

should_deploy() {
  local name="$1"
  if [ -z "$ONLY_SERVICES" ]; then
    return 0
  fi
  case ",$ONLY_SERVICES," in
    *",$name,"*) return 0 ;;
    *) return 1 ;;
  esac
}

should_force() {
  local name="$1"
  case ",$FORCE_SERVICES," in
    *",$name,"*) return 0 ;;
    *) return 1 ;;
  esac
}
EOF

  python3 <<'PY' >> "$DEPLOY_SCRIPT_LOCAL"
import re, os

content = open("terraform.tfvars").read()
block = re.search(r'microservices\s*=\s*\[(.*?)\n\]', content, re.S)
if not block:
    exit(0)

for m in re.finditer(r'\{(.*?)\}', block.group(1), re.S):
    svc = dict(re.findall(r'(\w+)\s*=\s*"([^"]+)"', m.group(1)))
    name = svc["name"]
    repo = svc["repo_url"]
    branch = svc.get("branch", "main")

    print(f'''
echo "Deploying {name}"
DIR="/home/ubuntu/{name}"

if should_deploy "{name}"; then
  if [ -d "$DIR" ] && ! should_force "{name}"; then
    echo "{name} ya existe"
  else
    rm -rf "$DIR"
    git clone -b "{branch}" --depth=1 "{repo}" "$DIR"
    cd "$DIR"
    if [ -f docker-compose.yml ] || [ -f docker-compose.yaml ]; then
      docker-compose up -d
    fi
    cd /home/ubuntu
  fi
fi
''')
PY

  sed -i "s/__ONLY__/${ONLY_SERVICES}/" "$DEPLOY_SCRIPT_LOCAL"
  sed -i "s/__FORCE__/${FORCE_SERVICES}/" "$DEPLOY_SCRIPT_LOCAL"

  chmod +x "$DEPLOY_SCRIPT_LOCAL"
}

# ============================================================================
# DEPLOY
# ============================================================================

deploy_microservices() {
  echo -e "${BLUE}Iniciando despliegue de microservicios...${NC}"
  echo ""

  get_vm_info
  echo ""

  detect_ssh_opts
  echo ""

  check_vm_running
  echo ""

  echo -e "${BLUE}Generando script de despliegue...${NC}"
  generate_deploy_script
  echo -e "${GREEN}Script generado${NC}"
  echo ""

  # El usuario ya se determinó en detect_ssh_opts (OS Login o ubuntu)
  # Mostrar información del usuario
  if [[ -z "$SSH_USER" ]]; then
    echo -e "${BLUE}Usando OS Login (usuario automático)${NC}"
  else
    echo -e "${BLUE}Usando usuario: $SSH_USER${NC}"
  fi
  echo ""

  # Función para intentar copiar con timeout
  try_scp() {
    local ssh_opts="$1"
    local timeout_sec="${2:-60}"

    echo -e "${BLUE}Copiando script (timeout: ${timeout_sec}s)...${NC}"
    # Construir destino: usuario@instancia o solo instancia (si OS Login)
    local scp_dest
    if [[ -n "$SSH_USER" ]]; then
      scp_dest="$SSH_USER@$INSTANCE_NAME:$DEPLOY_SCRIPT_REMOTE"
    else
      scp_dest="$INSTANCE_NAME:$DEPLOY_SCRIPT_REMOTE"
    fi

    if timeout "$timeout_sec" gcloud compute scp "$DEPLOY_SCRIPT_LOCAL" \
      "$scp_dest" \
      --zone="$INSTANCE_ZONE" \
      --project="$PROJECT_ID" \
      $ssh_opts \
      --quiet \
      --verbosity=error \
      --scp-flag="-o ServerAliveInterval=30" \
      --scp-flag="-o ServerAliveCountMax=3" 2>&1; then
      return 0
    else
      local exit_code=$?
      if [[ $exit_code -eq 124 ]]; then
        echo -e "${YELLOW}Timeout al copiar (${timeout_sec}s)${NC}"
      fi
      return $exit_code
    fi
  }

  # Intentar copiar con IAP primero (prioridad 1)
  if ! try_scp "$SSH_OPTS" 60; then
    # Si IAP falla, intentar con IP pública (prioridad 2)
    if [[ -n "$VM_IP" && "$VM_IP" != "None" ]]; then
      echo -e "${YELLOW}IAP falló, intentando con IP pública...${NC}"
      SSH_OPTS=""
      SSH_USER="ubuntu"
      if ! try_scp "$SSH_OPTS" 60; then
        # Si IP pública falla, intentar OS Login (prioridad 3)
        if [[ "$OS_LOGIN_ENABLED" == "TRUE" ]]; then
          echo -e "${YELLOW}IP pública falló, intentando con OS Login...${NC}"
          SSH_OPTS=""
          SSH_USER=""
          if ! try_scp "$SSH_OPTS" 60; then
            echo -e "${RED}Error: No se pudo copiar el script (IAP, IP pública ni OS Login funcionaron)${NC}" >&2
            rm -f "$DEPLOY_SCRIPT_LOCAL"
            exit 1
          fi
        else
          echo -e "${RED}Error: No se pudo copiar el script (IAP e IP pública fallaron)${NC}" >&2
          rm -f "$DEPLOY_SCRIPT_LOCAL"
          exit 1
        fi
      fi
    else
      # No hay IP pública, intentar OS Login si está disponible
      if [[ "$OS_LOGIN_ENABLED" == "TRUE" ]]; then
        echo -e "${YELLOW}IAP falló, intentando con OS Login...${NC}"
        SSH_OPTS=""
        SSH_USER=""
        if ! try_scp "$SSH_OPTS" 60; then
          echo -e "${RED}Error: No se pudo copiar el script (IAP ni OS Login funcionaron)${NC}" >&2
          rm -f "$DEPLOY_SCRIPT_LOCAL"
          exit 1
        fi
      else
        echo -e "${RED}Error: No se pudo copiar el script (IAP falló y no hay alternativas)${NC}" >&2
        rm -f "$DEPLOY_SCRIPT_LOCAL"
        exit 1
      fi
    fi
  fi

  echo -e "${GREEN}Script copiado${NC}"
  echo ""

  # Función para ejecutar deploy con timeout
  try_ssh_deploy() {
    local ssh_opts="$1"
    local timeout_sec="${2:-300}"

    echo -e "${BLUE}Ejecutando deploy (timeout: ${timeout_sec}s)...${NC}"
    # Construir comando SSH: usuario@instancia o solo instancia (si OS Login)
    local ssh_target
    if [[ -n "$SSH_USER" ]]; then
      ssh_target="$SSH_USER@$INSTANCE_NAME"
      # Con usuario específico, asegurar permisos
      local user_home="/home/$SSH_USER"
      local perm_cmd="sudo chown -R $SSH_USER:$SSH_USER $user_home /tmp/deploy-microservices.sh 2>/dev/null || true;"
    else
      ssh_target="$INSTANCE_NAME"
      # Con OS Login, el usuario se determina automáticamente
      local perm_cmd=""
    fi

    # Ejecutar deploy con permisos y script
    if timeout "$timeout_sec" gcloud compute ssh "$ssh_target" \
      --zone="$INSTANCE_ZONE" \
      --project="$PROJECT_ID" \
      $ssh_opts \
      --quiet \
      --ssh-flag="-o ServerAliveInterval=30" \
      --ssh-flag="-o ServerAliveCountMax=3" \
      --command="${perm_cmd}chmod +x $DEPLOY_SCRIPT_REMOTE 2>/dev/null || true; \
        bash $DEPLOY_SCRIPT_REMOTE && rm -f $DEPLOY_SCRIPT_REMOTE" 2>&1; then
      return 0
    else
      local exit_code=$?
      if [[ $exit_code -eq 124 ]]; then
        echo -e "${YELLOW}Timeout al ejecutar deploy (${timeout_sec}s)${NC}"
      fi
      return $exit_code
    fi
  }

  # Ejecutar deploy con el mismo método que funcionó para SCP
  # (ya se probó IAP > IP pública > OS Login en try_scp)
  if ! try_ssh_deploy "$SSH_OPTS" 300; then
    echo -e "${RED}Error: No se pudo ejecutar el deploy${NC}" >&2
    echo -e "${RED}El método de conexión que funcionó para copiar no funciona para ejecutar${NC}" >&2
    rm -f "$DEPLOY_SCRIPT_LOCAL"
    exit 1
  fi

  rm -f "$DEPLOY_SCRIPT_LOCAL"
  echo ""
  echo -e "${GREEN}Deploy completado${NC}"
}

show_ssh_command() {
  get_vm_info
  detect_ssh_opts

  echo ""
  echo -e "${BLUE}Comando SSH para conectarse a la VM:${NC}"
  echo ""
  echo "gcloud compute ssh $INSTANCE_NAME \\"
  echo "  --zone=$INSTANCE_ZONE \\"
  echo "  --project=$PROJECT_ID \\"
  echo "  $SSH_OPTS"
  echo ""
  echo -e "${BLUE}Para ejecutarlo directamente, copia y pega el comando de arriba${NC}"
  echo ""
}

# ============================================================================
# MAIN
# ============================================================================

case "$ACTION" in
  --apply) apply_terraform ;;
  --apply-deploy) apply_terraform; deploy_microservices ;;
  --deploy-only) deploy_microservices ;;
  --ssh) show_ssh_command ;;
  ""|--help|-h) show_help ;;
  *)
    echo -e "${RED}Opción no reconocida: $ACTION${NC}" >&2
    exit 1
    ;;
esac
