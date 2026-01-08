#!/bin/bash
set -e
set -x  # Debug: mostrar comandos ejecutados

# Log para debugging
exec > >(tee /var/log/certbot-install.log) 2>&1
echo "=== Iniciando instalación de Certbot ==="
echo "Fecha: $(date)"
echo "Usuario: $(whoami)"

# Actualizar sistema
apt-get update -y

# Instalar Certbot
apt-get install -y certbot

# Verificar instalación
certbot --version

echo "=== Instalación de Certbot completada ==="
