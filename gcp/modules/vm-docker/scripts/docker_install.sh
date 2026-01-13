#!/bin/bash
set -euo pipefail

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

exec > >(tee /var/log/docker-install.log) 2>&1

# Actualizar sistema
apt-get update -y

# Instalar dependencias
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git \
  make \
  nano \
  wget \
  unzip

# Agregar clave GPG de Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Agregar repositorio de Docker
echo \
  "deb [arch=$(dpkg --print-architecture) " \
  "signed-by=/etc/apt/keyrings/docker.gpg] " \
  "https://download.docker.com/linux/ubuntu " \
  "$(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Instalar Docker Compose si está habilitado
%{ if install_docker_compose ~}
DOCKER_COMPOSE_BASE="https://github.com/docker/compose/releases/download"
DOCKER_COMPOSE_VERSION="${docker_compose_version}"
DOCKER_COMPOSE_ARCH="$(uname -s)-$(uname -m)"
DOCKER_COMPOSE_URL="$DOCKER_COMPOSE_BASE/$DOCKER_COMPOSE_VERSION/docker-compose-$DOCKER_COMPOSE_ARCH"
curl -L "$DOCKER_COMPOSE_URL" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sfn /usr/local/bin/docker-compose /usr/bin/docker-compose
%{ endif ~}

# Agregar usuarios al grupo docker
for user in $(getent passwd | awk -F: '$3 >= 1000 {print $1}'); do
  if id "$user" &>/dev/null; then
    user_shell=$(getent passwd "$user" | cut -d: -f7)
    if [ "$user_shell" != "/usr/sbin/nologin" ] && \
       [ "$user_shell" != "/bin/false" ]; then
      if ! groups "$user" | grep -q "\bdocker\b"; then
        usermod -aG docker "$user" || true
      fi
    fi
  fi
done

# Habilitar Docker al inicio
systemctl enable docker
systemctl start docker

# Verificar instalación
docker --version
%{ if install_docker_compose ~}
docker-compose --version
%{ endif ~}

sleep 5

if docker ps &>/dev/null; then
  echo -e "$${GREEN}Docker installed and running$${NC}"
else
  echo -e "$${YELLOW}Docker installed but may require session restart$${NC}"
fi
