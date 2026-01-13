# Casos de Uso: VM Docker

Este documento describe todos los casos de uso disponibles en `machines/vm-docker` y cómo utilizarlos.

## Tabla de Contenidos

1. [Creación de VM con Docker](#1-creación-de-vm-con-docker)
2. [Despliegue de Microservicios](#2-despliegue-de-microservicios)
3. [Conexión SSH](#3-conexión-ssh)
4. [Diagnóstico y Troubleshooting](#4-diagnóstico-y-troubleshooting)
5. [Gestión de Claves SSH](#5-gestión-de-claves-ssh)
6. [Actualización de Microservicios](#6-actualización-de-microservicios)
7. [Configuración por Ambientes](#7-configuración-por-ambientes)
8. [Scripts de Despliegue Personalizados](#8-scripts-de-despliegue-personalizados)
9. [Configuración Avanzada](#9-configuración-avanzada)

---

## 1. Creación de VM con Docker

### Caso 1.1: VM Básica con Docker

Crear una VM con Docker instalado, sin microservicios.

```bash
cd machines/vm-docker
terraform init
terraform apply
```

**Configuración mínima en `terraform.tfvars`:**

```hcl
project_id = "mi-proyecto"
vm_subnet_name = "workspace-dev-vpc-vm-subnet"
service_account_email = "vm-reader@mi-proyecto.iam.gserviceaccount.com"
instance_name = "vm-docker-dev"
```

**Resultado:**
- VM creada con Docker instalado
- Docker Compose instalado (por defecto)
- Claves SSH generadas automáticamente
- Scripts de gestión copiados a `/opt/scripts/`

### Caso 1.2: VM con Certbot (SSL)

Crear una VM con Docker y Certbot para gestionar certificados SSL.

```hcl
# En terraform.tfvars
install_certbot = true
tags = ["allow-http", "allow-https"]
```

**Resultado:**
- Certbot instalado
- Listo para gestionar certificados SSL automáticamente

### Caso 1.3: VM sin IP Pública (solo IAP)

Crear una VM sin IP pública, accesible solo vía IAP (Identity-Aware Proxy).

```hcl
# En terraform.tfvars
enable_public_ip = false
tags = ["allow-iap-ssh"]
```

**Requisitos:**
- IAP habilitado en el proyecto
- Firewall rules configuradas para IAP
- Tag `allow-iap-ssh` en la VM

**Resultado:**
- VM sin IP pública
- Acceso SSH solo vía IAP
- Más segura (sin exposición pública)

### Caso 1.4: VM con IP Pública Estática

Crear una VM con IP pública estática (no cambia al reiniciar).

```hcl
# En terraform.tfvars
enable_public_ip = true
static_public_ip = "mi-vm-ip-estatica"
```

**Resultado:**
- IP pública estática asignada
- IP no cambia al reiniciar la VM
- Útil para servicios que requieren IP fija

### Caso 1.5: VM con IP Interna Estática

Crear una VM con IP interna estática (dentro de la VPC).

```hcl
# En terraform.tfvars
static_internal_ip = "10.0.0.10"  # Debe estar en el rango de la subnet
```

**Resultado:**
- IP interna estática asignada
- Útil para servicios internos con IP fija

---

## 2. Despliegue de Microservicios

### Caso 2.1: Despliegue Automático de Microservicios

Desplegar microservicios automáticamente al crear la VM.

```hcl
# En terraform.tfvars
microservices = [
  {
    name           = "gateway"
    repo_url       = "https://github.com/usuario/gateway.git"
    branch         = "staging"
    env_file       = "envs/gateway.env"
    launch_command = null
  },
  {
    name           = "api-service"
    repo_url       = "https://github.com/usuario/api-service.git"
    branch         = "main"
    env_file       = "envs/api.env"
    launch_command = "docker-compose up -d"
  }
]
```

**Resultado:**
- Microservicios clonados automáticamente
- Archivos `.env` creados
- Contenedores iniciados (si tienen `docker-compose.yml`)

### Caso 2.2: Microservicio con Comando Personalizado

Desplegar un microservicio con comando de lanzamiento personalizado.

```hcl
microservices = [
  {
    name           = "local-deps"
    repo_url       = "https://github.com/usuario/local-deps.git"
    branch         = "develop"
    env_file       = "envs/local-deps.env"
    launch_command = "make launch SERVICIOS=postgres"
  }
]
```

**Resultado:**
- Repositorio clonado
- Archivo `.env` creado
- Comando personalizado ejecutado

### Caso 2.3: Microservicio con Variables de Entorno Directas

Definir variables de entorno directamente en `terraform.tfvars` (para archivos pequeños).

```hcl
microservices = [
  {
    name           = "simple-app"
    repo_url       = "https://github.com/usuario/simple-app.git"
    branch         = "main"
    env_file       = <<-EOF
      ALLOWED_HOSTS=example.com
      DEBUG=false
      DATABASE_URL=postgresql://user:pass@localhost/db
    EOF
    launch_command = null
  }
]
```

**Resultado:**
- Archivo `.env` creado con el contenido directo
- Sin necesidad de archivo separado en `envs/`

### Caso 2.4: Actualización Automática de Microservicios

El sistema actualiza automáticamente los microservicios cuando cambias `terraform.tfvars`.

**Flujo:**
1. Modificas `terraform.tfvars` (agregas nuevo microservicio)
2. Ejecutas `terraform apply`
3. Terraform actualiza el metadata de la VM
4. Timer systemd detecta el cambio (máximo 1-2 minutos)
5. Nuevo microservicio se despliega automáticamente

**Ventajas:**
- No requiere SSH
- No requiere gcloud
- Totalmente automático
- Funciona sin IP pública

---

## 3. Conexión SSH

### Caso 3.1: Conectarse por SSH usando Makefile (Recomendado)

Usar el Makefile para conectarse automáticamente (detecta .pem > .json > IAP > OS Login > IP pública).

```bash
cd machines/vm-docker
make ssh
```

**Características:**
- Detecta automáticamente el método de conexión
- Prioridad: .pem > .json > IAP > OS Login > IP pública
- Muestra información de conexión
- Conecta interactivamente

**Alternativa (script directo):**
```bash
./scripts/ssh.sh
```

### Caso 3.2: Conectarse vía IAP (sin IP pública)

Conectarse cuando la VM no tiene IP pública (usa IAP automáticamente).

```bash
make ssh
# Automáticamente detecta y usa IAP si no hay .pem o .json
```

**Requisitos:**
- Tag `allow-iap-ssh` en la VM
- IAP habilitado en el proyecto
- Permisos IAM adecuados

### Caso 3.3: Conectarse con IP Pública

Conectarse directamente usando la IP pública.

```bash
# Obtener IP pública
terraform output external_ip

# Conectarse con la clave generada
ssh -i keys/$(terraform output -raw instance_name).pem \
    ubuntu@$(terraform output -raw external_ip)
```

### Caso 3.4: Obtener Comando SSH

Obtener el comando SSH sin conectarse.

```bash
# Usando Makefile (recomendado)
make ssh-cmd

# O usando Terraform output
terraform output ssh_command
```

---

## 4. Diagnóstico y Troubleshooting

### Caso 4.1: Diagnosticar Problemas de IAP/SSH

Ejecutar diagnóstico completo de conexión IAP/SSH.

```bash
cd machines/vm-docker
make diagnose-iap
# O directamente:
./scripts/diagnose-iap.sh
```

**Verifica:**
- Estado de la VM
- IP pública (si existe)
- Tags de la VM
- Firewall rules para IAP
- IAP API habilitado
- Permisos IAP del usuario
- Test de conectividad

**Resultado:**
- Reporte detallado de configuración
- Recomendaciones para corregir problemas
- Comandos para solucionar

### Caso 4.2: Diagnosticar Actualización de Microservicios (desde VM)

Diagnosticar problemas con la actualización automática desde dentro de la VM.

```bash
# Conectarse a la VM
make ssh

# Ejecutar diagnóstico
bash /opt/scripts/diagnose_update.sh
```

**Verifica:**
- Estado del timer systemd
- Existencia de scripts
- Permisos
- Metadata actual
- Hash guardado

---

## 5. Gestión de Claves SSH

### Caso 5.1: Restaurar Clave SSH Perdida

Restaurar la clave SSH cuando se pierde el acceso.

```bash
cd machines/vm-docker
make restore-ssh
# O directamente:
./scripts/restore-ssh-key.sh
```

**Características:**
- Obtiene clave pública desde Terraform
- Usa IAP para conectarse (no requiere acceso SSH previo)
- Agrega clave a `~/.ssh/authorized_keys` o metadata de la VM
- Fallback automático si IAP falla

**Requisitos:**
- Terraform aplicado al menos una vez
- IAP habilitado (preferido) o acceso alternativo
- Permisos para modificar metadata

### Caso 5.2: Ver Clave SSH Generada

Ver la clave SSH pública generada por Terraform.

```bash
# Ver output
terraform output ssh_public_key

# Ver archivo
cat keys/$(terraform output -raw instance_name).pub
```

### Caso 5.3: Usar Clave SSH Personalizada

Usar tus propias claves SSH en lugar de la generada.

```hcl
# En terraform.tfvars
ssh_keys = [
  "ubuntu:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB... tu-clave-publica"
]
```

**Resultado:**
- Tu clave SSH agregada a la VM
- Puedes conectarte con tu clave privada

---

## 6. Actualización de Microservicios

### Caso 6.1: Agregar Nuevo Microservicio

Agregar un nuevo microservicio a la VM existente.

```hcl
# 1. Editar terraform.tfvars
microservices = [
  # ... microservicios existentes ...
  {
    name           = "nuevo-servicio"
    repo_url       = "https://github.com/usuario/nuevo-servicio.git"
    branch         = "main"
    env_file       = "envs/nuevo-servicio.env"
    launch_command = null
  }
]

# 2. Aplicar cambios
terraform apply
```

**Resultado:**
- Metadata actualizado automáticamente
- Nuevo microservicio desplegado en 1-2 minutos (automático)

### Caso 6.2: Actualizar Microservicio Existente (Manual)

Actualizar el código de un microservicio existente.

```bash
# Opción 1: Usando Makefile (recomendado)
make ssh-exec CMD="bash /opt/scripts/helper_update_services.sh update-one gateway"

# Opción 2: Conectarse a la VM y ejecutar
make ssh
bash /opt/scripts/helper_update_services.sh update-one gateway

# Opción 3: Manualmente
make ssh
cd /home/ubuntu/gateway
git pull origin staging
docker-compose down
docker-compose up -d --build
```

### Caso 6.3: Actualizar Todos los Microservicios

Actualizar todos los microservicios a la vez.

```bash
# Usando Makefile (recomendado)
make update-all

# O conectarse a la VM y ejecutar manualmente
make ssh
bash /opt/scripts/helper_update_services.sh update-all
```

**Resultado:**
- Todos los microservicios actualizados con `git pull`
- Contenedores reconstruidos y reiniciados

### Caso 6.4: Re-desplegar Microservicio

Eliminar y volver a desplegar un microservicio desde cero.

```bash
# Conectarse a la VM
make ssh

# Usar script helper
bash /opt/scripts/helper_update_services.sh redeploy gateway

# O manualmente
rm -rf /home/ubuntu/gateway
bash /opt/scripts/helper_update_services.sh update-from-metadata
```

**Útil cuando:**
- Cambió el archivo `.env`
- Cambió el branch en `terraform.tfvars`
- Problemas con el despliegue actual

### Caso 6.5: Desplegar Microservicios Nuevos

Desplegar microservicios nuevos después de agregarlos a `terraform.tfvars`.

```bash
# Opción 1: Usando Makefile (recomendado)
make deploy

# Opción 2: Manualmente con script
./scripts/deploy-microservices.sh --deploy-only

# Opción 3: Esperar actualización automática (1-2 minutos)
# El sistema detecta cambios automáticamente mediante timer systemd
```

**Nota:** El método automático (timer systemd) es preferido y no requiere SSH. Usa `make deploy` solo si necesitas forzar el despliegue inmediatamente.

---

## 7. Configuración por Ambientes

### Caso 7.1: Usar Archivo de Configuración por Ambiente

Usar diferentes archivos de configuración según el ambiente.

```bash
# Desarrollo
terraform apply -var-file=terraform.tfvars.dev

# QA
terraform apply -var-file=terraform.tfvars.qa

# Staging (archivo principal)
terraform apply

# Producción
terraform apply -var-file=terraform.tfvars.prod
```

**Archivos:**
- `terraform.tfvars` - Staging (archivo principal)
- `terraform.tfvars.example` - Template de referencia
- Crea `terraform.tfvars.<ambiente>` copiando desde `.example` según necesites

### Caso 7.2: Configuración Multi-Ambiente

Mantener múltiples VMs (una por ambiente) con la misma configuración base.

```bash
# VM de desarrollo
cd machines/vm-docker
terraform workspace new dev
terraform apply -var-file=terraform.tfvars.dev

# VM de staging (workspace default)
terraform workspace select default
terraform apply
```

**Nota:** Usa `terraform.tfvars.example` como base para crear archivos por ambiente.

---

## 8. Scripts de Despliegue Personalizados

### Caso 8.1: Copiar Scripts Personalizados a la VM

Copiar scripts y archivos grandes (>256KB) que no caben en metadata.

```hcl
# En terraform.tfvars
deployment_scripts = "../custom-scripts"
deployment_scripts_destination = "/home/ubuntu/configuration"
```

**Proceso:**
1. Configurar variables en `terraform.tfvars`
2. Ejecutar `terraform apply`
3. Usar output para ejecutar script de copia:

```bash
terraform output -json copy_deployment_scripts_info | jq -r '
  "./modules/vm-docker/scripts/copy_deployment_scripts.sh " +
  .instance_name + " " +
  .zone + " " +
  .project_id + " " +
  .destination + " " +
  .source + " " +
  .user
' | bash
```

**Requisitos:**
- gcloud CLI instalado y autenticado
- VM con tag `allow-iap-ssh`
- IAP habilitado

**Resultado:**
- Scripts y archivos copiados a la VM
- Disponibles en el directorio destino especificado

### Caso 8.2: Script de Inicio Personalizado

Agregar comandos personalizados al script de inicio.

```hcl
# En terraform.tfvars
metadata_startup_script = <<-EOF
  # Instalar paquetes adicionales
  apt-get update
  apt-get install -y vim htop

  # Configurar alias
  echo 'alias ll="ls -la"' >> ~/.bashrc
EOF
```

**Resultado:**
- Comandos ejecutados durante el startup
- Integrado con el script de instalación de Docker

---

## 9. Configuración Avanzada

### Caso 9.1: Usar Remote State

Conectar con infraestructura compartida usando remote state.

```hcl
# En terraform.tfvars
shared_infra_state_bucket = "mi-bucket-terraform-state"
shared_infra_state_prefix = "shared-infra/dev"
```

**Ventajas:**
- Obtiene automáticamente `vm_subnet_name` y `service_account_email`
- No necesitas especificarlos manualmente
- Consistente con la infraestructura compartida

### Caso 9.2: Configuración Completa con Todas las Opciones

Ejemplo completo con todas las opciones configuradas.

```hcl
# En terraform.tfvars

# Información básica
project_id = "mi-proyecto"
region     = "us-central1"
zone       = "us-central1-a"
instance_name = "vm-docker-prod"

# Infraestructura
vm_subnet_name = "workspace-prod-vpc-vm-subnet"
service_account_email = "vm-reader@mi-proyecto.iam.gserviceaccount.com"

# Hardware
machine_type = "e2-standard-4"
boot_disk_size = 50
boot_disk_type = "pd-ssd"

# Red
enable_public_ip = true
static_public_ip = "vm-docker-prod-ip"
static_internal_ip = "10.0.1.10"

# Docker
install_docker_compose = true
install_certbot = true
use_ubuntu_image = true

# Microservicios
environment = "prod"
microservices = [
  {
    name           = "api"
    repo_url       = "https://github.com/usuario/api.git"
    branch         = "production"
    env_file       = "envs/api.prod.env"
    launch_command = null
  }
]

# Etiquetas
tags = ["allow-http", "allow-https", "allow-iap-ssh"]
labels = {
  environment = "prod"
  team        = "backend"
  managed_by  = "terraform"
}
```

### Caso 9.3: Ver Outputs de Terraform

Ver todos los outputs disponibles después de `terraform apply`.

```bash
# Ver todos los outputs
terraform output

# Ver output específico
terraform output instance_name
terraform output external_ip
terraform output ssh_command
terraform output ssh_private_key_path

# Ver en JSON
terraform output -json
```

---

## Resumen de Comandos Disponibles

### Comandos Makefile (Recomendado)

| Comando | Descripción | Caso de Uso |
|---------|-------------|-------------|
| `make ssh` | Conectarse por SSH (auto-detecta método) | Conexión SSH |
| `make deploy` | Desplegar microservicios nuevos | Despliegue |
| `make update-all` | Actualizar todos los microservicios | Actualización |
| `make restore-ssh` | Restaurar clave SSH perdida | Gestión de claves |
| `make diagnose-iap` | Diagnosticar problemas IAP/SSH | Troubleshooting |
| `make logs` | Ver logs del startup script | Diagnóstico |
| `make status` | Ver estado de la VM | Monitoreo |

**Ver todos los comandos:**
```bash
make help
```

### Scripts Locales (en `./scripts/`)

Los scripts también están disponibles directamente si prefieres usarlos sin Makefile:
- `ssh.sh` - Conexión SSH
- `diagnose-iap.sh` - Diagnóstico IAP/SSH
- `restore-ssh-key.sh` - Restaurar clave SSH
- `deploy-microservices.sh` - Desplegar microservicios (método manual)

### Scripts en la VM (en `/opt/scripts/`)

| Script | Descripción | Caso de Uso |
|--------|-------------|-------------|
| `update_microservices.sh` | Actualizar microservicios desde metadata | Actualización automática |
| `watch_metadata.sh` | Monitorear cambios en metadata | Actualización automática |
| `helper_update_services.sh` | Helper para gestión de microservicios | Gestión manual |
| `diagnose_update.sh` | Diagnosticar problemas de actualización | Troubleshooting |

---

## Flujos Comunes

### Flujo 1: Primera Vez - Crear VM con Microservicios

```bash
# 1. Configurar terraform.tfvars
vim terraform.tfvars

# 2. Inicializar Terraform
make init

# 3. Ver plan
make plan

# 4. Aplicar y ejecutar post-deploy
make up

# 5. Verificar despliegue
make ssh
docker ps
ls -la /home/ubuntu/
```

### Flujo 2: Agregar Nuevo Microservicio

```bash
# 1. Editar terraform.tfvars
vim terraform.tfvars  # Agregar nuevo microservicio

# 2. Aplicar
make apply

# 3. Opción A: Esperar actualización automática (1-2 minutos)
# El timer systemd detecta cambios automáticamente

# Opción B: Forzar despliegue inmediato
make deploy

# Opción C: Verificar manualmente
make ssh
bash /opt/scripts/helper_update_services.sh status
```

### Flujo 3: Actualizar Microservicio Existente

```bash
# Opción 1: Usando Makefile (recomendado)
make update-all  # Actualiza todos los microservicios

# Opción 2: Actualizar uno específico
make ssh
bash /opt/scripts/helper_update_services.sh update-one gateway

# 3. Verificar
make ssh
docker ps
docker logs gateway
```

### Flujo 4: Restaurar Acceso SSH Perdido

```bash
# 1. Desde el directorio del proyecto
cd machines/vm-docker

# 2. Restaurar clave
make restore-ssh

# 3. Verificar conexión
make ssh
```

### Flujo 5: Diagnosticar Problemas

```bash
# 1. Diagnosticar IAP/SSH
make diagnose-iap

# 2. Ver logs del startup script
make logs

# 3. Si hay acceso SSH, diagnosticar actualización
make ssh
bash /opt/scripts/diagnose_update.sh

# 4. Ver logs del sistema de monitoreo
make ssh
tail -f /var/log/watch-metadata.log
sudo journalctl -u watch-metadata.service -f
```

---

## Notas Importantes

1. **Actualización Automática**: El sistema actualiza automáticamente microservicios nuevos, pero NO actualiza los existentes. Usa `make update-all` o `helper_update_services.sh` para actualizar existentes.

2. **Sin IP Pública**: El sistema funciona perfectamente sin IP pública usando IAP. Esto es más seguro.

3. **Timer Systemd**: El timer ejecuta `watch_metadata.sh` cada minuto. Los cambios se detectan en máximo 1-2 minutos.

4. **Metadata vs Realidad**: El metadata refleja lo que está en `terraform.tfvars`, no necesariamente lo que está desplegado en la VM.

5. **Makefile**: Siempre preferir comandos del Makefile (`make ssh`, `make deploy`, etc.) sobre scripts directos. Son más consistentes y fáciles de usar.

6. **Usuario por Defecto**: El sistema usa `ubuntu` como usuario principal por defecto. Esto es configurable mediante la variable `MAIN_USER` en los scripts.

---

## Referencias

- **Flujo Completo**: Ver [FLUJO_DESPLIEGUE.md](./FLUJO_DESPLIEGUE.md) - Explicación detallada del proceso técnico
- **Troubleshooting**: Ver [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Solución de problemas comunes
- **Restaurar SSH**: Ver [RESTORE_SSH.md](./RESTORE_SSH.md) - Restaurar acceso SSH perdido
- **Módulo vm-docker**: Ver [../../modules/vm-docker/README.md](../../modules/vm-docker/README.md) - Documentación del módulo
