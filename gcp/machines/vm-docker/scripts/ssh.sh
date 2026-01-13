#!/usr/bin/env bash
# Script para conectarse por SSH a la VM con diagnóstico de IAP

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<EOF
Uso: $0 [--diagnose]

Conecta por SSH a la VM con prioridad: IAP > IP pública > OS Login

Opciones:
  --diagnose    Mostrar diagnóstico de IAP/SSH sin conectar

EOF
}

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

cd "$TERRAFORM_DIR"

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# VALIDACIONES INICIALES
# ============================================================================

# Verificar que gcloud esté instalado
if ! command -v gcloud &> /dev/null; then
  echo -e "${RED}Error: gcloud no está instalado o no está en PATH${NC}" >&2
  echo "   Instala gcloud: https://cloud.google.com/sdk/docs/install" >&2
  exit 1
fi

# Verificar autenticación de gcloud
echo -e "${BLUE}Verificando autenticación de gcloud...${NC}"
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1 || echo "")

if [[ -z "$ACTIVE_ACCOUNT" ]]; then
  echo -e "${RED}Error: No hay cuentas activas en gcloud${NC}" >&2
  echo "" >&2
  echo "   Para autenticarte, ejecuta:" >&2
  echo "   gcloud auth login" >&2
  echo "" >&2
  echo "   O si usas una Service Account:" >&2
  echo "   gcloud auth activate-service-account --key-file=/path/to/key.json" >&2
  exit 1
fi

echo -e "${GREEN}Autenticado como: $ACTIVE_ACCOUNT${NC}"
echo ""

# Verificar que la aplicación por defecto esté configurada
DEFAULT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [[ -z "$DEFAULT_PROJECT" ]]; then
  echo -e "${YELLOW}Advertencia: No hay proyecto por defecto configurado en gcloud${NC}" >&2
  echo "   Se usará el proyecto del terraform.tfvars" >&2
fi

# Obtener información de la VM
echo -e "${BLUE}Obteniendo información de la VM...${NC}"
INSTANCE_NAME=$(terraform output -raw instance_name 2>/dev/null || true)
INSTANCE_ZONE=$(terraform output -raw instance_zone 2>/dev/null || true)
PROJECT_ID=$(grep '^project_id' terraform.tfvars | sed 's/.*"\(.*\)".*/\1/' | head -1)

if [[ -z "$INSTANCE_NAME" || -z "$INSTANCE_ZONE" ]]; then
  echo -e "${RED}Error: No se pudo obtener información de la VM${NC}" >&2
  echo "   Asegúrate de haber ejecutado 'terraform apply' al menos una vez" >&2
  exit 1
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}Error: No se pudo obtener el PROJECT_ID del terraform.tfvars${NC}" >&2
  exit 1
fi

echo "   Instancia: $INSTANCE_NAME"
echo "   Zona: $INSTANCE_ZONE"
echo "   Proyecto: $PROJECT_ID"
echo ""

# Verificar estado de la VM
echo -e "${BLUE}Verificando estado de la VM...${NC}"
STATUS_OUTPUT=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  --format='value(status)' 2>&1)

STATUS_EXIT=$?

if [[ $STATUS_EXIT -ne 0 ]] || [[ -z "$STATUS_OUTPUT" ]]; then
  echo -e "${RED}Error al obtener el estado de la VM${NC}" >&2
  echo "   Error: $STATUS_OUTPUT" >&2
  echo "   Código de salida: $STATUS_EXIT" >&2
  exit 1
fi

STATUS="$STATUS_OUTPUT"

if [[ "$STATUS" != "RUNNING" ]]; then
  echo -e "${RED}Error: La VM no está en estado RUNNING (estado: $STATUS)${NC}" >&2
  echo "   La VM debe estar en estado RUNNING para conectarse por SSH" >&2
  exit 1
fi

echo -e "${GREEN}VM está corriendo${NC}"
echo ""

# Obtener información de red
IP=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || echo "")

TAGS=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  --format='value(tags.items)' 2>/dev/null || echo "")

NETWORK=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  --format='value(networkInterfaces[0].network)' 2>/dev/null || echo "")

# Obtener network_name desde la subnet de la VM (si está disponible)
SUBNET_NAME=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  --format='get(networkInterfaces[0].subnetwork)' 2>/dev/null | xargs basename 2>/dev/null || echo "")

# Extraer network_name del nombre de la subnet (formato: network_name-vm-subnet)
if [[ -n "$SUBNET_NAME" && "$SUBNET_NAME" =~ ^(.+)-vm-subnet$ ]]; then
  NETWORK_NAME="${BASH_REMATCH[1]}"
else
  NETWORK_NAME=""
fi

IAP_TAG="${NETWORK_NAME:+${NETWORK_NAME}-}allow-iap-ssh"
SSH_TAG="${NETWORK_NAME:+${NETWORK_NAME}-}allow-ssh"

# Función para diagnosticar IAP
diagnose_iap() {
  echo -e "${BLUE}Diagnóstico de IAP:${NC}"
  echo ""

  # Verificar tag (soporta ambos formatos: con y sin network_name)
  if [[ "$TAGS" == *"$IAP_TAG"* ]] || [[ "$TAGS" == *"allow-iap-ssh"* ]]; then
    echo -e "${GREEN}Tag de IAP encontrado en la VM${NC}"
  else
    echo -e "${RED}Tag de IAP NO encontrado en la VM${NC}"
    echo "   Tags actuales: $TAGS"
    if [[ -n "$NETWORK_NAME" ]]; then
      echo "   Tag esperado: $IAP_TAG"
    fi
  fi

  # Verificar firewall rule
  echo ""
  echo -e "${BLUE}Verificando firewall rules para IAP...${NC}"
  FIREWALL_FILTER="name~allow-iap-ssh"
  if [[ -n "$NETWORK_NAME" ]]; then
    FIREWALL_FILTER="name~${NETWORK_NAME}-allow-iap-ssh OR name~allow-iap-ssh"
  fi
  FIREWALL_RULE=$(gcloud compute firewall-rules list \
    --project="$PROJECT_ID" \
    --filter="$FIREWALL_FILTER" \
    --format="value(name)" 2>/dev/null | head -1 || echo "")

  if [[ -n "$FIREWALL_RULE" ]]; then
    echo -e "${GREEN}Firewall rule encontrada: $FIREWALL_RULE${NC}"
  else
    echo -e "${YELLOW}No se encontró firewall rule específica para IAP${NC}"
    echo "   Verificando reglas generales de SSH..."
  fi

  # Verificar si IAP está habilitado en el proyecto
  echo ""
  echo -e "${BLUE}Verificando si IAP está habilitado...${NC}"
  IAP_ENABLED=$(gcloud services list --enabled \
    --project="$PROJECT_ID" \
    --filter="name:iap.googleapis.com" \
    --format="value(name)" 2>/dev/null || echo "")

  if [[ -n "$IAP_ENABLED" ]]; then
    echo -e "${GREEN}IAP API está habilitado${NC}"
  else
    echo -e "${YELLOW}IAP API podría no estar habilitado${NC}"
    echo "   Para habilitarlo: gcloud services enable iap.googleapis.com --project=$PROJECT_ID"
  fi

  echo ""
}

# Función para intentar conexión con timeout
try_ssh() {
  local ssh_opts="$1"
  local timeout_seconds="${2:-30}"

  echo -e "${BLUE}Intentando conexión SSH (timeout: ${timeout_seconds}s)...${NC}"
  echo ""

  # Capturar tanto stdout como stderr para diagnóstico
  # Forzar usuario ubuntu explícitamente
  SSH_OUTPUT=$(timeout "$timeout_seconds" gcloud compute ssh "$SSH_USER@$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --project="$PROJECT_ID" \
    $ssh_opts \
    --command="echo 'Conexión exitosa'" 2>&1)

  SSH_EXIT=$?

  if [[ $SSH_EXIT -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}Conexión SSH funciona correctamente${NC}"
    return 0
  else
    echo ""
    if [[ $SSH_EXIT -eq 124 ]]; then
      echo -e "${RED}Timeout: La conexión se quedó colgada después de ${timeout_seconds} segundos${NC}"
    elif [[ $SSH_EXIT -eq 1 ]]; then
      echo -e "${RED}Error al conectar${NC}"
      echo ""
      echo "   Detalles del error:"
      echo "$SSH_OUTPUT" | grep -i "error\|denied\|permission\|auth" | \
        head -5 | sed 's/^/   /' || echo "   (No se pudo obtener detalles específicos)"
      echo ""
      echo "   Posibles causas:"
      echo "   - Problemas de autenticación (ejecuta: gcloud auth login)"
      echo "   - Firewall bloqueando la conexión"
      echo "   - La VM no está completamente lista"
      echo "   - Problemas con IAP (si no hay IP pública)"
      echo "   - El usuario ubuntu no existe o no tiene permisos"
    else
      echo -e "${RED}Error al conectar (código: $SSH_EXIT)${NC}"
      echo ""
      echo "   Salida:"
      echo "$SSH_OUTPUT" | head -10 | sed 's/^/   /'
    fi
    return 1
  fi
}

# Forzar uso del usuario ubuntu siempre
SSH_USER="ubuntu"
echo -e "${BLUE}Usando usuario: $SSH_USER (forzado)${NC}"
echo ""

# Determinar método de conexión
# Prioridad: IAP > IP pública > OS Login

# Mostrar diagnóstico si se solicita
if [[ "${1:-}" == "--diagnose" ]]; then
  diagnose_iap
  exit 0
fi

# Inicializar variables
SSH_OPTS=""
CONNECTION_METHOD=""

# Prioridad 1: Intentar con IAP primero
echo -e "${BLUE}Prioridad 1: Intentando con IAP...${NC}"
SSH_OPTS="--tunnel-through-iap"

if try_ssh "$SSH_OPTS" 30; then
  echo ""
  echo -e "${GREEN}IAP funciona correctamente${NC}"
  CONNECTION_METHOD="IAP"
else
  echo ""
  echo -e "${YELLOW}IAP falló, intentando con IP pública (prioridad 2)...${NC}"

  # Prioridad 2: Intentar con IP pública si existe
  if [[ -n "$IP" && "$IP" != "None" ]]; then
    SSH_OPTS=""

    if try_ssh "$SSH_OPTS" 15; then
      echo ""
      echo -e "${GREEN}IP pública funciona correctamente${NC}"
      CONNECTION_METHOD="IP_PUBLICA"
    else
      echo ""
      echo -e "${YELLOW}IP pública falló, intentando con OS Login (prioridad 3)...${NC}"

      # Prioridad 3: Intentar con OS Login pero forzando usuario ubuntu
      SSH_OPTS=""
      # Intentar con usuario ubuntu explícitamente incluso con OS Login
      if timeout 15 gcloud compute ssh "$SSH_USER@$INSTANCE_NAME" \
        --zone="$INSTANCE_ZONE" \
        --project="$PROJECT_ID" \
        $SSH_OPTS \
        --command="echo 'Conexión exitosa'" 2>&1 | grep -q "Conexión exitosa"; then
        echo ""
        echo -e "${GREEN}OS Login funciona correctamente (con usuario ubuntu)${NC}"
        CONNECTION_METHOD="OS_LOGIN"
      else
        echo ""
        echo -e "${RED}Ningún método de conexión funciona (IAP, IP pública ni OS Login)${NC}"
        echo ""
        echo -e "${BLUE}Opciones:${NC}"
        echo "   1. Ejecuta diagnóstico: $0 --diagnose"
        echo "   2. Verifica firewall rules y tags manualmente"
        echo "   3. Verifica que la VM esté completamente iniciada"
        exit 1
      fi
    fi
  else
    echo ""
    echo -e "${YELLOW}No hay IP pública disponible, intentando con OS Login (prioridad 3)...${NC}"

    # Prioridad 3: Intentar con OS Login pero forzando usuario ubuntu
    SSH_OPTS=""
    # Intentar con usuario ubuntu explícitamente incluso con OS Login
    if timeout 15 gcloud compute ssh "$SSH_USER@$INSTANCE_NAME" \
      --zone="$INSTANCE_ZONE" \
      --project="$PROJECT_ID" \
      $SSH_OPTS \
      --command="echo 'Conexión exitosa'" 2>&1 | grep -q "Conexión exitosa"; then
      echo ""
      echo -e "${GREEN}OS Login funciona correctamente (con usuario ubuntu)${NC}"
      CONNECTION_METHOD="OS_LOGIN"
    else
      echo ""
      echo -e "${RED}Ningún método de conexión funciona (IAP ni OS Login)${NC}"
      echo ""
      echo -e "${BLUE}Opciones:${NC}"
      echo "   1. Ejecuta diagnóstico: $0 --diagnose"
      echo "   2. Verifica firewall rules y tags manualmente"
      echo "   3. Verifica que la VM esté completamente iniciada"
      exit 1
    fi
  fi
fi

# Mostrar información del método seleccionado
echo ""
echo -e "${BLUE}Usuario: $SSH_USER (forzado)${NC}"
echo -e "${BLUE}Método de conexión: $CONNECTION_METHOD${NC}"
echo ""

echo ""
echo -e "${BLUE}Comando SSH:${NC}"
echo "gcloud compute ssh $SSH_USER@$INSTANCE_NAME \\"
echo "  --zone=$INSTANCE_ZONE \\"
echo "  --project=$PROJECT_ID \\"
echo "  $SSH_OPTS"
echo ""

# Ejecutar SSH interactivo
echo -e "${BLUE}Conectando...${NC}"
echo "   (Presiona Ctrl+C si se queda colgado)"
echo ""

# Usar exec para reemplazar el proceso actual
# Agregar flags para mejorar la conexión
# Forzar usuario ubuntu explícitamente siempre
exec gcloud compute ssh "$SSH_USER@$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  $SSH_OPTS \
  --ssh-flag="-o ServerAliveInterval=30" \
  --ssh-flag="-o ServerAliveCountMax=3"
