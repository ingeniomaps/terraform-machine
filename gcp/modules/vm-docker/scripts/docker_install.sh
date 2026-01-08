#!/bin/bash
set -e
set -x  # Debug: mostrar comandos ejecutados

# Log para debugging
exec > >(tee /var/log/docker-install.log) 2>&1
echo "=== Iniciando instalación de Docker ==="
echo "Fecha: $(date)"
echo "Usuario: $(whoami)"
echo "Distribución: $(lsb_release -cs)"

# Actualizar sistema
apt-get update -y

# Instalar dependencias
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git

# Agregar clave GPG de Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Agregar repositorio de Docker (usar ubuntu, no debian)
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker (usando repositorio oficial de Docker)
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Instalar Docker Compose si está habilitado
%{ if install_docker_compose ~}
curl -L "https://github.com/docker/compose/releases/download/${docker_compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sfn /usr/local/bin/docker-compose /usr/bin/docker-compose
%{ endif ~}

# Agregar usuario ubuntu al grupo docker (si existe)
if id "ubuntu" &>/dev/null; then
  usermod -aG docker ubuntu || true
fi
# También agregar el usuario actual si no es ubuntu
CURRENT_USER=$(whoami || echo "ubuntu")
if [ "$CURRENT_USER" != "ubuntu" ] && id "$CURRENT_USER" &>/dev/null; then
  usermod -aG docker "$CURRENT_USER" || true
fi

# Habilitar Docker al inicio
systemctl enable docker
systemctl start docker

# Verificar instalación
docker --version
%{ if install_docker_compose ~}
docker-compose --version
%{ endif ~}

# Esperar a que Docker esté completamente iniciado
sleep 5

# Verificar que Docker está funcionando
if docker ps &>/dev/null; then
  echo "✅ Docker instalado y funcionando correctamente"
else
  echo "⚠️  Docker instalado pero puede requerir reinicio de sesión para usar sin sudo"
fi

echo "=== Instalación de Docker completada ==="
