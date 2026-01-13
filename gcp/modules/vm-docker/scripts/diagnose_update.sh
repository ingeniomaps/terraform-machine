#!/bin/bash
set -euo pipefail

# ============================================================================
# CONFIGURACIÓN: Usuario principal de la VM
# ============================================================================
# Cambiar este valor si el usuario principal de la VM es diferente
readonly MAIN_USER="${MAIN_USER:-ubuntu}"
readonly MAIN_USER_HOME="/home/${MAIN_USER}"

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

echo -e "${BLUE}=== Microservices Update Diagnosis ===${NC}"
echo ""

echo "1. Checking update script:"
UPDATE_SCRIPT="/opt/scripts/update_microservices.sh"
if [ -f "$UPDATE_SCRIPT" ]; then
  echo -e "   ${GREEN}Script exists: $UPDATE_SCRIPT${NC}"
  echo "   Permissions: $(ls -la "$UPDATE_SCRIPT" | awk '{print $1}')"
else
  echo -e "   ${RED}Script NOT found: $UPDATE_SCRIPT${NC}"
  echo "   Startup script may not have finished"
  exit 1
fi

echo ""
echo "2. Checking microservices metadata:"
METADATA_RAW=$(curl -s -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/microservices_json 2>&1)

if [ -n "$METADATA_RAW" ]; then
  echo -e "   ${GREEN}Metadata exists${NC}"
  echo "   Content (base64): ${METADATA_RAW:0:50}..."

  if command -v base64 &> /dev/null; then
    MICROSERVICES_JSON=$(echo "$METADATA_RAW" | base64 -d)
    if [ -n "$MICROSERVICES_JSON" ]; then
      echo -e "   ${GREEN}JSON decoded successfully${NC}"
      echo "   Content (first 200 chars): ${MICROSERVICES_JSON:0:200}..."
    else
      echo -e "   ${RED}Error decoding JSON${NC}"
      exit 1
    fi
  else
    echo -e "   ${YELLOW}base64 not available${NC}"
  fi
else
  echo -e "   ${RED}Metadata NOT found${NC}"
  echo "   Verify terraform.tfvars has microservices configured"
  exit 1
fi

echo ""
echo "3. Checking current services in $MAIN_USER_HOME:"
cd "$MAIN_USER_HOME" || exit 1
if [ -d . ]; then
  echo "   Directories found:"
  for dir in */; do
    if [ -d "$dir/.git" ]; then
      echo "   • $dir (git repo)"
    else
      echo "   • $dir (no git)"
    fi
  done
else
  echo -e "   ${YELLOW}Cannot access $MAIN_USER_HOME${NC}"
fi

echo ""
echo "4. Testing update script execution:"
if [ -n "$MICROSERVICES_JSON" ]; then
  echo "   Executing: bash $UPDATE_SCRIPT \"\$MICROSERVICES_JSON\""
  echo ""
  bash "$UPDATE_SCRIPT" "$MICROSERVICES_JSON" 2>&1 | head -50
else
  echo -e "   ${YELLOW}Cannot execute: no decoded JSON${NC}"
fi

echo ""
echo -e "${BLUE}=== Diagnosis completed ===${NC}"
