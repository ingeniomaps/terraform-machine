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
readonly NC='\033[0m'

LOG_FILE="/var/log/watch-metadata.log"
UPDATE_SCRIPT="/opt/scripts/update_microservices.sh"
METADATA_KEY="microservices_json"
LAST_HASH_FILE="/tmp/microservices_last_hash.txt"

# Asegurar permisos de log
if [ "$(id -u)" = "0" ]; then
  touch "$LOG_FILE" 2>/dev/null || true
  chown "${MAIN_USER}:${MAIN_USER}" "$LOG_FILE" 2>/dev/null || true
  chmod 664 "$LOG_FILE" 2>/dev/null || true
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_metadata() {
  curl -s -H 'Metadata-Flavor: Google' \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${METADATA_KEY}" 2>/dev/null || echo ""
}

get_metadata_hash() {
  local metadata_content="$1"
  [ -n "$metadata_content" ] && echo "$metadata_content" | sha256sum | cut -d' ' -f1 || echo ""
}

if [ ! -f "$UPDATE_SCRIPT" ]; then
  log "ERROR: Update script not found: $UPDATE_SCRIPT"
  exit 1
fi

# Obtener metadata actual
METADATA_CONTENT=$(get_metadata)
CURRENT_HASH=$(get_metadata_hash "$METADATA_CONTENT")

# Leer hash anterior
LAST_HASH=""
[ -f "$LAST_HASH_FILE" ] && LAST_HASH=$(cat "$LAST_HASH_FILE")

# Comparar hashes
if [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
  if [ -z "$CURRENT_HASH" ]; then
    log "WARNING: Metadata '${METADATA_KEY}' is empty or missing"
  else
    log "Change detected in metadata (hash: ${CURRENT_HASH:0:16}...)"
    log "Executing microservices update..."

    if command -v base64 &> /dev/null; then
      MICROSERVICES_JSON=$(echo "$METADATA_CONTENT" | base64 -d)

      if [ -n "$MICROSERVICES_JSON" ]; then
        # Ejecutar como MAIN_USER para tener permisos correctos
        if sudo -u "$MAIN_USER" bash "$UPDATE_SCRIPT" "$MICROSERVICES_JSON" >> "$LOG_FILE" 2>&1; then
          log "Microservices update completed successfully"
          echo "$CURRENT_HASH" > "$LAST_HASH_FILE"
        else
          log "ERROR: Microservices update failed"
          exit 1
        fi
      else
        log "WARNING: Microservices JSON is empty after decoding"
      fi
    else
      log "ERROR: base64 command not available"
      exit 1
    fi
  fi
else
  log "No changes detected in metadata (hash: ${CURRENT_HASH:0:16}...)"
fi
