#!/bin/bash
set -e

cd /home/ubuntu

# Desplegar cada microservicio
%{ for service in microservices ~}
echo "Desplegando microservicio: ${service.name}"
PROJECT=${service.name}

# Clonar repositorio
git clone ${service.repo_url} -b ${service.branch} --depth=1 || true

cd $${PROJECT}

# Crear archivo .env
cat > .env <<'ENVEOF'
${service.env_file}
ENVEOF

# Ejecutar script de instalación si existe
if [ -f "installer.sh" ]; then
  bash installer.sh
elif [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
  docker-compose up -d
fi

cd ..
%{ endfor ~}

echo "Despliegue de microservicios completado"
