# Módulo VM Docker

Crea una instancia de Compute Engine (VM) configurada para ejecutar contenedores Docker y desplegar microservicios desde repositorios Git con actualización automática basada en metadata.

## 📋 Descripción

El módulo `vm-docker` extiende `vm-base` y agrega:

- **Instalación de Docker**: Instala Docker y Docker Compose automáticamente
- **Despliegue de Microservicios**: Clona repositorios Git y despliega servicios usando Docker Compose
- **Monitoreo Automático**: Sistema de monitoreo basado en metadata que actualiza microservicios automáticamente
- **Certbot** (opcional): Instalación de Certbot para certificados SSL

## 🔧 Variables Principales

| Variable                         | Tipo           | Descripción                                 | Default                        | Requerido |
| -------------------------------- | -------------- | ------------------------------------------- | ------------------------------ | --------- |
| `project_id`                     | `string`       | ID del proyecto GCP                         | -                              | ✅        |
| `instance_name`                  | `string`       | Nombre de la instancia VM                   | -                              | ✅        |
| `vm_subnet_name`                 | `string`       | Nombre de la subnet                         | -                              | ✅        |
| `service_account_email`          | `string`       | Service Account para la VM                  | -                              | ✅        |
| `region`                         | `string`       | Región donde se creará la VM                | `"us-central1"`                | ❌        |
| `zone`                           | `string`       | Zona donde se creará la VM                  | `"us-central1-a"`              | ❌        |
| `machine_type`                   | `string`       | Tipo de máquina                             | `"e2-medium"`                  | ❌        |
| `boot_disk_size`                 | `number`       | Tamaño del disco (GB)                       | `20`                           | ❌        |
| `enable_public_ip`               | `bool`         | Habilitar IP pública                        | `false`                        | ❌        |
| `static_public_ip`               | `string`       | Nombre para IP pública estática             | `null`                         | ❌        |
| `use_ubuntu_image`               | `bool`         | Usar imagen Ubuntu                          | `false`                        | ❌        |
| `install_docker_compose`         | `bool`         | Instalar Docker Compose                     | `true`                         | ❌        |
| `docker_compose_version`         | `string`       | Versión de Docker Compose                   | `"v2.33.0"`                    | ❌        |
| `install_certbot`                | `bool`         | Instalar Certbot                            | `false`                        | ❌        |
| `metadata_startup_script`        | `string`       | Script de inicio personalizado              | `""`                           | ❌        |
| `deployment_scripts`             | `string`       | Ruta local a scripts/archivos               | `""`                           | ❌        |
| `deployment_scripts_destination` | `string`       | Directorio destino en la VM                 | `"/home/ubuntu/configuration"` | ❌        |
| `microservices`                  | `list(object)` | Lista de microservicios a desplegar         | `[]`                           | ❌        |
| `environment`                    | `string`       | Ambiente de despliegue (no usado actualmente) | `"dev"`                        | ❌        |

### Estructura de `microservices`

```hcl
microservices = [
  {
    name           = "api"
    repo_url       = "https://github.com/user/api.git"
    branch         = "main"
    env_file       = "envs/api.env"  # Ruta relativa o contenido del archivo .env
    launch_command = null  # Comando personalizado (obligatorio, puede ser null)
  }
]
```

**Notas importantes:**
- `launch_command` es obligatorio pero puede ser `null`
- Si `launch_command` es `null` o vacío, el script intentará usar `installer.sh` o `docker-compose.yml`
- `env_file` puede ser una ruta relativa (ej: `"envs/api.env"`) o contenido directo del archivo

## 📤 Outputs

| Output                  | Descripción                               |
| ----------------------- | ----------------------------------------- |
| `instance_id`           | ID de la instancia VM                     |
| `instance_name`         | Nombre de la instancia                    |
| `instance_zone`         | Zona de la instancia                      |
| `internal_ip`           | IP interna de la instancia                |
| `external_ip`           | IP externa (null si no tiene IP pública)  |
| `static_public_ip_name` | Nombre del recurso de IP pública estática |
| `ssh_command`           | Comando SSH para conectarse vía IAP       |
| `self_link`             | Self link de la instancia                 |
| `copy_deployment_scripts_info` | Información para copiar scripts de despliegue manualmente |

## 📝 Ejemplo de Uso

### Configuración Básica

```hcl
module "vm_docker" {
  source = "../../modules/vm-docker"

  project_id            = "my-project-id"
  region                = "us-central1"
  zone                  = "us-central1-a"
  instance_name         = "docker-vm"
  vm_subnet_name        = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"

  enable_public_ip = true
  use_ubuntu_image = true
  tags             = ["allow-http"]
}
```

### Con Microservicios desde Git

```hcl
module "vm_docker" {
  source = "../../modules/vm-docker"

  project_id            = "my-project-id"
  region                = "us-central1"
  zone                  = "us-central1-a"
  instance_name         = "docker-vm"
  vm_subnet_name        = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"

  enable_public_ip = true
  use_ubuntu_image = true

  microservices = [
    {
      name           = "api"
      repo_url       = "https://github.com/user/api.git"
      branch         = "main"
      env_file       = "envs/api.env"
      launch_command = null
    },
    {
      name           = "worker"
      repo_url       = "https://github.com/user/worker.git"
      branch         = "develop"
      env_file       = "envs/worker.env"
      launch_command = "docker-compose up -d"
    }
  ]

  tags = ["allow-http"]
}
```

### Con Scripts de Despliegue Personalizados (Archivos Grandes)

Para copiar archivos grandes (> 256KB), múltiples archivos o directorios completos:

```hcl
module "vm_docker" {
  source = "../../modules/vm-docker"

  project_id            = "my-project-id"
  region                = "us-central1"
  zone                  = "us-central1-a"
  instance_name         = "docker-vm"
  vm_subnet_name        = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"

  enable_public_ip              = true
  use_ubuntu_image              = true
  deployment_scripts            = "./scripts/deploy"  # Directorio local
  deployment_scripts_destination = "/home/ubuntu/deployment"  # Destino en VM

  tags = ["allow-http", "allow-iap-ssh"]  # allow-iap-ssh necesario para SCP
}
```

Después de `terraform apply`, ejecuta manualmente:

```bash
./modules/vm-docker/scripts/copy_deployment_scripts.sh \
  <instance_name> <zone> <project_id> \
  <destination> <source> <user>
```

**Requisitos**: gcloud CLI instalado y autenticado, VM con tag "allow-iap-ssh"

**Nota**: Para scripts pequeños (< 256KB), usa `metadata_startup_script`.

### Con Certbot para SSL

```hcl
module "vm_docker" {
  source = "../../modules/vm-docker"

  project_id            = "my-project-id"
  region                = "us-central1"
  zone                  = "us-central1-a"
  instance_name         = "docker-vm"
  vm_subnet_name        = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"

  enable_public_ip = true
  install_certbot  = true
  use_ubuntu_image = true

  tags = ["allow-http", "allow-https"]
}
```

## 🔄 Actualización Automática de Microservicios

El módulo incluye un sistema de monitoreo automático:

1. **Metadata**: Los microservicios se almacenan en metadata de la VM como JSON codificado en base64
2. **Monitoreo**: Un script (`watch_metadata.sh`) monitorea cambios en el metadata cada minuto
3. **Actualización**: Cuando detecta cambios, ejecuta automáticamente el despliegue de nuevos microservicios
4. **Systemd Timer**: Usa un timer systemd para ejecutar el monitoreo periódicamente

**Para actualizar microservicios:**
- Modifica la variable `microservices` en `terraform.tfvars`
- Ejecuta `terraform apply`
- El sistema detectará los cambios automáticamente y actualizará los microservicios

## 🔗 Dependencias

Este módulo requiere:

- **Subnet**: La subnet especificada en `vm_subnet_name` debe existir (normalmente creada por el módulo `network` de `shared-infra`)
- **Service Account**: El Service Account especificado en `service_account_email` debe existir (normalmente creado por el módulo `security` de `shared-infra`)
- **Firewall Rules**: Si se expone HTTP/HTTPS, las reglas de firewall correspondientes deben existir en `shared-infra`

## 📚 Scripts Incluidos

El módulo incluye scripts que se copian automáticamente a la VM durante el startup:

- **`docker_install.sh`**: Instala Docker y Docker Compose
- **`certbot_install.sh`**: Instala Certbot (si está habilitado)
- **`microservices_deploy.sh`**: Despliega microservicios desde repositorios Git (ejecutado en startup)
- **`update_microservices.sh`**: Actualiza microservicios cuando cambia el metadata
- **`watch_metadata.sh`**: Monitorea cambios en metadata y ejecuta actualizaciones (ejecutado por systemd timer)
- **`helper_update_services.sh`**: Script helper para actualización manual desde dentro de la VM
- **`diagnose_update.sh`**: Script de diagnóstico para troubleshooting

## ⚠️ Notas Importantes

1. **Imagen Base**: Por defecto usa Container-Optimized OS. Si `use_ubuntu_image = true`, usa Ubuntu 22.04 LTS.
2. **Docker Compose**: Se instala automáticamente si `install_docker_compose = true` y `use_ubuntu_image = true`.
3. **Microservicios**: Se clonan desde Git y se despliegan usando Docker Compose o comandos personalizados (`launch_command`).
4. **Environment Files**: Los archivos `.env` pueden ser rutas relativas (se leen automáticamente) o contenido directo.
5. **Scripts de Despliegue**: Para scripts grandes (> 256KB) o directorios, usa `deployment_scripts`. Para scripts pequeños, usa `metadata_startup_script`.
6. **Actualización Automática**: Los cambios en `microservices` se detectan automáticamente mediante metadata y systemd timers (cada minuto).

## 🔒 Seguridad

- La VM usa un Service Account con permisos mínimos
- Las claves SSH y variables de entorno se configuran mediante metadata (sensitive)
- Los scripts de despliegue se ejecutan con los permisos del usuario configurado (ubuntu por defecto)
