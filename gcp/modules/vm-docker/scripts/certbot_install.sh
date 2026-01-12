#!/bin/bash
set -euo pipefail

# Colores
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

exec > >(tee /var/log/certbot-install.log) 2>&1

# Actualizar sistema
apt-get update -y

# Instalar Certbot
apt-get install -y certbot

# Verificar instalación
certbot --version

echo -e "$${GREEN}Certbot installed successfully$${NC}"
