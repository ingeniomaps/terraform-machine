#!/usr/bin/env bash
# Script de diagnóstico completo para problemas de IAP/SSH

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<EOF
Uso: $0

Diagnostica problemas de conexión IAP/SSH con la VM.

Verifica:
- Estado de la VM
- IP pública
- Tags de la VM
- Firewall rules
- IAP API habilitado
- Permisos IAP del usuario
- Test de conectividad

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

# Obtener información de la VM
INSTANCE_NAME=$(terraform output -raw instance_name 2>/dev/null || true)
INSTANCE_ZONE=$(terraform output -raw instance_zone 2>/dev/null || true)
PROJECT_ID=$(grep '^project_id' terraform.tfvars | sed 's/.*"\(.*\)".*/\1/' | head -1)

if [[ -z "$INSTANCE_NAME" || -z "$INSTANCE_ZONE" ]]; then
  echo -e "${RED}Error: No se pudo obtener información de la VM${NC}" >&2
  exit 1
fi

echo "=========================================="
echo -e "${BLUE}DIAGNÓSTICO DE IAP/SSH${NC}"
echo "=========================================="
echo ""
echo "VM: $INSTANCE_NAME"
echo "Zona: $INSTANCE_ZONE"
echo "Proyecto: $PROJECT_ID"
echo ""

# 1. Estado de la VM
echo -e "${BLUE}1. Estado de la VM:${NC}"
STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  --format='get(status)' 2>/dev/null || echo "UNKNOWN")
echo "   Estado: $STATUS"
if [[ "$STATUS" != "RUNNING" ]]; then
  echo -e "${YELLOW}   La VM no está corriendo${NC}"
fi
echo ""

# 2. IP pública
echo -e "${BLUE}2. IP pública:${NC}"
IP=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || echo "None")
if [[ -z "$IP" || "$IP" == "None" ]]; then
  echo -e "${RED}   No tiene IP pública (requiere IAP)${NC}"
else
  echo -e "${GREEN}   IP pública: $IP${NC}"
fi
echo ""

# Obtener network_name desde la subnet de la VM (formato: network_name-vm-subnet)
SUBNET_NAME=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  --format='get(networkInterfaces[0].subnetwork)' 2>/dev/null | xargs basename 2>/dev/null || echo "")

# Extraer network_name del nombre de la subnet (formato: network_name-vm-subnet)
if [[ -n "$SUBNET_NAME" && "$SUBNET_NAME" =~ ^(.+)-vm-subnet$ ]]; then
  NETWORK_NAME="${BASH_REMATCH[1]}"
else
  # Fallback: intentar obtener desde terraform output
  NETWORK_NAME=$(terraform output -raw network_name 2>/dev/null || echo "")
  if [[ -z "$NETWORK_NAME" ]]; then
    # Último fallback: usar formato genérico
    NETWORK_NAME="workspace-dev"
    echo -e "${YELLOW}   No se pudo detectar network_name, usando fallback: $NETWORK_NAME${NC}"
  fi
fi

IAP_TAG="${NETWORK_NAME}-allow-iap-ssh"
SSH_TAG="${NETWORK_NAME}-allow-ssh"

# 3. Tags de la VM
echo -e "${BLUE}3. Tags de la VM:${NC}"
TAGS=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --project="$PROJECT_ID" \
  --format='get(tags.items)' 2>/dev/null || echo "")
echo "   Tags: $TAGS"
echo "   Network name detectado: $NETWORK_NAME"
echo "   Tag esperado para IAP: $IAP_TAG"
if [[ "$TAGS" == *"$IAP_TAG"* ]] || [[ "$TAGS" == *"allow-iap-ssh"* ]]; then
  echo -e "${GREEN}   Tag de IAP presente${NC}"
else
  echo -e "${RED}   Tag de IAP NO encontrado${NC}"
  echo "   Agrega el tag:"
  echo "   gcloud compute instances add-tags $INSTANCE_NAME \\"
  echo "     --tags=$IAP_TAG --zone=$INSTANCE_ZONE --project=$PROJECT_ID"
fi
echo ""

# 4. Firewall rules
echo -e "${BLUE}4. Firewall rules para IAP:${NC}"
FIREWALL_NAME="${NETWORK_NAME}-allow-iap-ssh"
echo "   Buscando regla compartida: $FIREWALL_NAME"

# Verificar si existe la regla específica para esta VM
FIREWALL_EXISTS=$(gcloud compute firewall-rules describe "$FIREWALL_NAME" \
  --project="$PROJECT_ID" \
  --format="value(name)" 2>/dev/null || echo "")

if [[ -n "$FIREWALL_EXISTS" ]]; then
  echo -e "${GREEN}   Regla '$FIREWALL_NAME' existe${NC}"
  echo "   Detalles:"
  gcloud compute firewall-rules describe "$FIREWALL_NAME" \
    --project="$PROJECT_ID" \
    --format="yaml(sourceRanges,targetTags,allowed,network)" 2>/dev/null | sed 's/^/      /'
else
  echo -e "${YELLOW}   Regla '$FIREWALL_NAME' NO existe${NC}"
fi

# Buscar otras reglas que puedan permitir IAP
echo ""
echo "   Buscando otras reglas que permitan IAP..."
# Listar todas las reglas y filtrar las que tienen allow-iap-ssh o el rango IAP
ALL_FIREWALLS=$(gcloud compute firewall-rules list \
  --project="$PROJECT_ID" \
  --format="table(name,direction,priority,sourceRanges,targetTags)" 2>/dev/null || echo "")

# Filtrar reglas que tienen allow-iap-ssh en targetTags o en el nombre
FIREWALL_RULES=$(echo "$ALL_FIREWALLS" | grep -A 1000 "NAME" | \
  grep -iE "allow-iap-ssh|${NETWORK_NAME}-allow-iap-ssh" || echo "")

if [[ -n "$FIREWALL_RULES" ]]; then
  echo "$FIREWALL_RULES" | head -20
  # Verificar si alguna tiene el rango de IAP
  if echo "$FIREWALL_RULES" | grep -q "35.235.240.0/20"; then
    echo -e "${GREEN}   Se encontraron reglas de firewall para IAP con el rango correcto${NC}"
  else
    echo -e "${YELLOW}   Se encontraron reglas con tag allow-iap-ssh pero sin el rango IAP (35.235.240.0/20)${NC}"
    echo "   Verifica que las reglas permitan el rango IAP: 35.235.240.0/20"
  fi
else
  if [[ -n "$FIREWALL_EXISTS" ]]; then
    echo "   Solo existe la regla específica '$FIREWALL_NAME' (esto está bien)"
    echo -e "${GREEN}   La regla encontrada arriba es suficiente para IAP${NC}"
  else
    echo -e "${YELLOW}   No se encontraron reglas específicas para IAP${NC}"
    echo "   Verifica que exista una regla que permita SSH desde el rango IAP: 35.235.240.0/20"
  fi
fi
echo ""

# 5. IAP API habilitado
echo -e "${BLUE}5. IAP API:${NC}"
IAP_ENABLED=$(gcloud services list --enabled \
  --project="$PROJECT_ID" \
  --filter="name:iap.googleapis.com" \
  --format="value(name)" 2>/dev/null || echo "")
if [[ -n "$IAP_ENABLED" ]]; then
  echo -e "${GREEN}   IAP API está habilitado${NC}"
else
  echo -e "${RED}   IAP API NO está habilitado${NC}"
  echo "   Habilítalo: gcloud services enable iap.googleapis.com --project=$PROJECT_ID"
fi
echo ""

# 6. Permisos IAP
echo -e "${BLUE}6. Permisos IAP del usuario actual:${NC}"
CURRENT_USER=$(gcloud config get-value account 2>/dev/null || echo "unknown")
echo "   Usuario: $CURRENT_USER"

IAP_ROLES=$(gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:$CURRENT_USER" \
  --format="value(bindings.role)" 2>/dev/null | grep -i "iap\|compute" || echo "")

if [[ -n "$IAP_ROLES" ]]; then
  echo "   Roles encontrados:"
  echo "$IAP_ROLES" | sed 's/^/      - /'
  if echo "$IAP_ROLES" | grep -q "iap.tunnelResourceAccessor\|compute.instanceAdmin\|owner"; then
    echo -e "${GREEN}   Tienes permisos para usar IAP${NC}"
  else
    echo -e "${YELLOW}   Podrías no tener permisos suficientes para IAP${NC}"
    echo "   Necesitas: roles/iap.tunnelResourceAccessor o roles/compute.instanceAdmin.v1"
  fi
else
  echo -e "${YELLOW}   No se encontraron roles relacionados con IAP/Compute${NC}"
fi
echo ""

# 7. Test de conectividad
echo -e "${BLUE}7. Test de conectividad:${NC}"
if [[ -z "$IP" || "$IP" == "None" ]]; then
  echo "   Probando conexión IAP (timeout 15s)..."
  TEST_OUTPUT=$(timeout 15 gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --project="$PROJECT_ID" \
    --tunnel-through-iap \
    --ssh-flag="-o ServerAliveInterval=5" \
    --command="echo 'OK'" 2>&1 || echo "FAILED")

  if echo "$TEST_OUTPUT" | grep -q "OK"; then
    echo -e "${GREEN}   Conexión IAP funciona correctamente${NC}"
  elif echo "$TEST_OUTPUT" | grep -q "timeout\|TIMEOUT"; then
    echo -e "${RED}   Timeout: La conexión IAP se queda colgada${NC}"
    echo "   Esto puede indicar problemas de red o configuración"
  else
    echo -e "${RED}   Error en la conexión:${NC}"
    echo "$TEST_OUTPUT" | tail -3 | sed 's/^/      /'
  fi
else
  echo "   Probando conexión directa (timeout 5s)..."
  TEST_OUTPUT=$(timeout 5 gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --project="$PROJECT_ID" \
    --command="echo 'OK'" 2>&1 || echo "FAILED")

  if echo "$TEST_OUTPUT" | grep -q "OK"; then
    echo -e "${GREEN}   Conexión directa funciona${NC}"
  else
    echo -e "${YELLOW}   Conexión directa no funciona, probando IAP...${NC}"
    TEST_OUTPUT=$(timeout 15 gcloud compute ssh "$INSTANCE_NAME" \
      --zone="$INSTANCE_ZONE" \
      --project="$PROJECT_ID" \
      --tunnel-through-iap \
      --ssh-flag="-o ServerAliveInterval=5" \
      --command="echo 'OK'" 2>&1 || echo "FAILED")

    if echo "$TEST_OUTPUT" | grep -q "OK"; then
      echo -e "${GREEN}   Conexión IAP funciona como alternativa${NC}"
    else
      echo -e "${RED}   Ninguna conexión funciona${NC}"
    fi
  fi
fi
echo ""

# 8. Resumen y recomendaciones
echo "=========================================="
echo -e "${BLUE}RESUMEN${NC}"
echo "=========================================="
echo ""

ISSUES=0

[[ "$STATUS" != "RUNNING" ]] && { echo -e "${RED}VM no está corriendo${NC}"; ((ISSUES++)); }
[[ "$TAGS" != *"allow-iap-ssh"* ]] && { echo -e "${RED}Falta tag allow-iap-ssh${NC}"; ((ISSUES++)); }
[[ -z "$FIREWALL_EXISTS" ]] && { echo -e "${RED}Falta firewall rule para IAP${NC}"; ((ISSUES++)); }
[[ -z "$IAP_ENABLED" ]] && { echo -e "${RED}IAP API no habilitado${NC}"; ((ISSUES++)); }

if [[ $ISSUES -eq 0 ]]; then
  echo -e "${GREEN}Configuración básica correcta${NC}"
else
  echo -e "${YELLOW}Se encontraron $ISSUES problema(s)${NC}"
fi
echo ""

echo "=========================================="
echo -e "${BLUE}RECOMENDACIONES${NC}"
echo "=========================================="
echo ""

if [[ "$STATUS" != "RUNNING" ]]; then
  echo "1. Inicia la VM:"
  echo "   gcloud compute instances start $INSTANCE_NAME --zone=$INSTANCE_ZONE --project=$PROJECT_ID"
  echo ""
fi

if [[ "$TAGS" != *"$IAP_TAG"* ]] && [[ "$TAGS" != *"allow-iap-ssh"* ]]; then
  echo "2. Agrega el tag de IAP:"
  echo "   gcloud compute instances add-tags $INSTANCE_NAME --tags=$IAP_TAG --zone=$INSTANCE_ZONE --project=$PROJECT_ID"
  echo ""
fi

if [[ -z "$FIREWALL_EXISTS" ]]; then
  echo "3. La firewall rule para IAP debería crearse automáticamente en shared-infra:"
  echo "   Nombre esperado: $FIREWALL_NAME"
  echo "   Si no existe, verifica que shared-infra esté aplicado correctamente"
  echo ""
fi

if [[ -z "$IAP_ENABLED" ]]; then
  echo "4. Habilita IAP API:"
  echo "   gcloud services enable iap.googleapis.com --project=$PROJECT_ID"
  echo ""
fi

if [[ -z "$IP" || "$IP" == "None" ]]; then
  echo "5. Si IAP no funciona, considera asignar una IP pública temporal:"
  echo "   gcloud compute instances add-access-config $INSTANCE_NAME \\"
  echo "     --zone=$INSTANCE_ZONE \\"
  echo "     --project=$PROJECT_ID \\"
  echo "     --access-config-name=external-nat"
  echo ""
fi

echo "6. Para usar SSH con las opciones recomendadas:"
echo "   ./scripts/ssh.sh"
echo ""
echo "7. Para ver todas las firewall rules:"
echo "   gcloud compute firewall-rules list --project=$PROJECT_ID --filter='allowed[].ports:22'"
echo ""

echo "=========================================="
