#!/bin/bash
# ============================================================================
# SCRIPT: Restaurar Clave SSH en la VM
# ============================================================================
# Este script restaura la clave SSH en la VM cuando se pierde el acceso
# Usa IAP para conectarse si no hay acceso SSH directo
# ============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$TERRAFORM_DIR"

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

usage() {
  echo -e "${RED}Uso: $0 [clave_publica]${NC}"
  echo "Si no se proporciona clave pública, se intentará obtener desde Terraform"
  exit 1
}

echo -e "${BLUE}Restaurando Clave SSH en la VM${NC}"
echo "=========================================="
echo ""

# Verificar que terraform está disponible
if ! command -v terraform &> /dev/null; then
  echo -e "${RED}Error: terraform no está instalado${NC}"
  exit 1
fi

# Verificar que gcloud está disponible
if ! command -v gcloud &> /dev/null; then
  echo -e "${RED}Error: gcloud no está instalado${NC}"
  echo "   Instala gcloud: https://cloud.google.com/sdk/docs/install"
  exit 1
fi

# Obtener información de la VM desde Terraform
echo -e "${BLUE}Obteniendo información de la VM desde Terraform...${NC}"

# Obtener outputs de Terraform
INSTANCE_NAME=$(terraform output -raw instance_name 2>/dev/null || echo "")
ZONE=$(terraform output -raw instance_zone 2>/dev/null || echo "")
PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || \
  terraform show -json 2>/dev/null | \
  jq -r '.values.root_module.resources[] | \
    select(.type == "google_compute_instance") | .values.project' | \
  head -1 || echo "")

# Si no se puede obtener desde outputs, intentar desde terraform.tfvars
if [ -z "$INSTANCE_NAME" ] || [ -z "$ZONE" ] || [ -z "$PROJECT_ID" ]; then
  echo -e "${YELLOW}No se pudo obtener información desde outputs, leyendo terraform.tfvars...${NC}"

  if [ -f "terraform.tfvars" ]; then
    INSTANCE_NAME=${INSTANCE_NAME:-$(grep -E "^instance_name\s*=" \
      terraform.tfvars | sed 's/.*=\s*"\(.*\)".*/\1/' | head -1)}
    ZONE=${ZONE:-$(grep -E "^zone\s*=" terraform.tfvars | sed 's/.*=\s*"\(.*\)".*/\1/' | head -1)}
    PROJECT_ID=${PROJECT_ID:-$(grep -E "^project_id\s*=" terraform.tfvars | sed 's/.*=\s*"\(.*\)".*/\1/' | head -1)}
  fi
fi

# Validar que tenemos la información necesaria
if [ -z "$INSTANCE_NAME" ]; then
  echo -e "${RED}Error: No se pudo obtener instance_name${NC}"
  echo "   Ejecuta: terraform output instance_name"
  exit 1
fi

if [ -z "$ZONE" ]; then
  echo -e "${RED}Error: No se pudo obtener zone${NC}"
  echo "   Ejecuta: terraform output instance_zone"
  exit 1
fi

if [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}Error: No se pudo obtener project_id${NC}"
  echo "   Verifica terraform.tfvars"
  exit 1
fi

echo -e "${GREEN}Información obtenida:${NC}"
echo "   Instancia: $INSTANCE_NAME"
echo "   Zona: $ZONE"
echo "   Proyecto: $PROJECT_ID"
echo ""

# Obtener la clave pública desde Terraform o argumento
if [ -n "${1:-}" ]; then
  PUBLIC_KEY="$1"
  echo -e "${GREEN}Clave pública proporcionada como argumento${NC}"
else
  echo -e "${BLUE}Obteniendo clave pública SSH desde Terraform...${NC}"

  # Intentar obtener desde output
  PUBLIC_KEY=$(terraform output -raw ssh_public_key 2>/dev/null || echo "")

  # Si no está en output, intentar leer desde el archivo generado
  if [ -z "$PUBLIC_KEY" ]; then
    # Obtener instance_name para construir el nombre del archivo
    KEY_FILE="keys/${INSTANCE_NAME}.pub"

    if [ -f "$KEY_FILE" ]; then
      PUBLIC_KEY=$(cat "$KEY_FILE")
      echo -e "${GREEN}Clave pública leída desde: $KEY_FILE${NC}"
    else
      echo -e "${YELLOW}Archivo de clave pública no encontrado: $KEY_FILE${NC}"
      echo "   Intentando obtener desde el estado de Terraform..."

      # Intentar obtener desde el estado de Terraform
      if terraform state show tls_private_key.vm_ssh_key &>/dev/null; then
        PUBLIC_KEY=$(terraform state show tls_private_key.vm_ssh_key 2>/dev/null | \
          grep "public_key_openssh" | sed 's/.*= "\(.*\)"/\1/' | head -1)
      fi
    fi
  fi
fi

if [ -z "$PUBLIC_KEY" ]; then
  echo -e "${RED}Error: No se pudo obtener la clave pública SSH${NC}"
  echo ""
  echo "   Soluciones:"
  echo "   1. Ejecuta 'terraform apply' para generar la clave"
  echo "   2. O proporciona la clave manualmente:"
  echo "      $0 <clave_publica_completa>"
  exit 1
fi

echo -e "${GREEN}Clave pública obtenida${NC}"
echo "   (primeros 50 caracteres: ${PUBLIC_KEY:0:50}...)"
echo ""

# Determinar usuario (normalmente ubuntu para Ubuntu)
USER="ubuntu"
if ! gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --project="$PROJECT_ID" \
  --format='get(metadata.items[ssh-keys])' 2>/dev/null | grep -q "ubuntu"; then
  # Intentar detectar el usuario desde las claves existentes
  EXISTING_KEYS=$(gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='get(metadata.items[ssh-keys])' 2>/dev/null || echo "")
  if [ -n "$EXISTING_KEYS" ]; then
    USER=$(echo "$EXISTING_KEYS" | head -1 | cut -d: -f1)
    echo -e "${YELLOW}Usuario detectado desde metadata: $USER${NC}"
  fi
fi

echo -e "${BLUE}Usuario: $USER${NC}"
echo ""

# Verificar que la VM está corriendo
echo -e "${BLUE}Verificando estado de la VM...${NC}"
STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --project="$PROJECT_ID" \
  --format='get(status)' 2>/dev/null || echo "UNKNOWN")

if [ "$STATUS" != "RUNNING" ]; then
  echo -e "${RED}Error: La VM no está en estado RUNNING (estado actual: $STATUS)${NC}"
  echo "   Inicia la VM primero:"
  echo "   gcloud compute instances start $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID"
  exit 1
fi

echo -e "${GREEN}VM está en estado RUNNING${NC}"
echo ""

# Preparar el comando para agregar la clave
# Formato: "usuario:clave_publica"
SSH_KEY_ENTRY="$USER:$PUBLIC_KEY"

echo -e "${BLUE}Agregando clave SSH a la VM...${NC}"
echo "   Método: IAP (Identity-Aware Proxy)"
echo ""

# Método 1: Intentar agregar directamente al authorized_keys vía IAP (más confiable)
echo -e "${BLUE}Conectándose vía IAP para agregar la clave...${NC}"

# Crear script temporal para ejecutar en la VM
TEMP_SCRIPT=$(mktemp)
cat > "$TEMP_SCRIPT" <<'SCRIPT_EOF'
#!/bin/bash
set -e
USER_HOME=$(eval echo ~$USER)
AUTHORIZED_KEYS="$USER_HOME/.ssh/authorized_keys"

# Crear directorio .ssh si no existe
mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"

# Agregar clave si no existe
if ! grep -q "$PUBLIC_KEY" "$AUTHORIZED_KEYS" 2>/dev/null; then
  echo "$PUBLIC_KEY" >> "$AUTHORIZED_KEYS"
  chmod 600 "$AUTHORIZED_KEYS"
  chown $USER:$USER "$AUTHORIZED_KEYS"
  echo "Clave agregada a $AUTHORIZED_KEYS"
  exit 0
else
  echo "La clave ya existe en $AUTHORIZED_KEYS"
  exit 0
fi
SCRIPT_EOF

# Reemplazar variable en el script
sed -i "s|\$PUBLIC_KEY|$PUBLIC_KEY|g" "$TEMP_SCRIPT"
sed -i "s|\$USER|$USER|g" "$TEMP_SCRIPT"

# Ejecutar script en la VM vía IAP
if gcloud compute ssh "$USER@$INSTANCE_NAME" \
  --zone="$ZONE" \
  --project="$PROJECT_ID" \
  --tunnel-through-iap \
  --command="bash -s" < "$TEMP_SCRIPT" 2>&1; then
  echo -e "${GREEN}Clave SSH agregada exitosamente al authorized_keys${NC}"
  rm -f "$TEMP_SCRIPT"
else
  echo -e "${YELLOW}No se pudo conectar vía IAP, intentando método alternativo...${NC}"
  rm -f "$TEMP_SCRIPT"

  # Método alternativo: Agregar al metadata de la instancia
  echo -e "${BLUE}Agregando clave al metadata de la instancia...${NC}"

  # Obtener claves existentes
  EXISTING_KEYS=$(gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='value(metadata.items[?key==`ssh-keys`].value)' 2>/dev/null || echo "")

  # Verificar si la clave ya existe
  if echo "$EXISTING_KEYS" | grep -q "$PUBLIC_KEY"; then
    echo -e "${YELLOW}La clave SSH ya existe en el metadata${NC}"
    echo "   No es necesario agregarla nuevamente"
    exit 0
  fi

  # Combinar claves existentes con la nueva
  if [ -n "$EXISTING_KEYS" ]; then
    ALL_KEYS=$(printf "%s\n%s" "$EXISTING_KEYS" "$SSH_KEY_ENTRY")
  else
    ALL_KEYS="$SSH_KEY_ENTRY"
  fi

  # Crear archivo temporal con todas las claves
  TEMP_KEYS_FILE=$(mktemp)
  echo "$ALL_KEYS" > "$TEMP_KEYS_FILE"

  # Agregar la clave al metadata de la instancia usando --metadata-from-file
  if gcloud compute instances add-metadata "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --metadata-from-file ssh-keys="$TEMP_KEYS_FILE" \
    --quiet 2>&1; then
    echo -e "${GREEN}Clave SSH agregada al metadata de la instancia${NC}"
    rm -f "$TEMP_KEYS_FILE"
  else
    echo -e "${RED}Error: No se pudo agregar la clave SSH${NC}"
    echo ""
    echo "   Posibles causas:"
    echo "   1. La VM no tiene el tag 'allow-iap-ssh'"
    echo "   2. IAP no está habilitado en el proyecto"
    echo "   3. No tienes permisos para usar IAP o modificar metadata"
    echo ""
    echo "   Solución manual:"
    echo "   1. Conéctate usando otra clave o método"
    echo "   2. Ejecuta manualmente:"
    echo "      echo '$PUBLIC_KEY' >> ~/.ssh/authorized_keys"
    rm -f "$TEMP_KEYS_FILE"
    exit 1
  fi
fi

echo ""
echo -e "${GREEN}Clave SSH restaurada exitosamente${NC}"
echo ""
echo -e "${BLUE}Próximos pasos:${NC}"
echo "   1. Verifica que puedes conectarte:"
echo "      ssh -i keys/${INSTANCE_NAME}.pem $USER@<IP_PUBLICA>"
echo ""
echo "   2. O usando IAP:"
echo "      gcloud compute ssh $USER@$INSTANCE_NAME \\"
echo "        --zone=$ZONE \\"
echo "        --project=$PROJECT_ID \\"
echo "        --tunnel-through-iap \\"
echo "        --ssh-key-file=keys/${INSTANCE_NAME}.pem"
echo ""
