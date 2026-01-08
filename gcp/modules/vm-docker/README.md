# Módulo VM Docker

Este módulo crea una instancia de Compute Engine (VM) configurada para ejecutar contenedores Docker. Soporta despliegue desde Docker Hub, scripts personalizados, y microservicios desde repositorios Git.

## 📋 Descripción

El módulo `vm-docker` extiende `vm-base` y agrega:

- **Instalación de Docker**: Instala Docker y Docker Compose automáticamente
- **Despliegue de Contenedores**: Soporta múltiples métodos de despliegue:
  - Imágenes Docker desde Docker Hub
  - Scripts de despliegue personalizados
  - Microservicios desde repositorios Git
- **Certbot** (opcional): Instalación de Certbot para certificados SSL
- **Health Checks**: Scripts de verificación de salud configurables

## 🔧 Variables Principales

| Variable                         | Tipo           | Descripción                         | Default                        | Requerido |
| -------------------------------- | -------------- | ----------------------------------- | ------------------------------ | --------- |
| `project_id`                     | `string`       | ID del proyecto GCP                 | -                              | ✅        |
| `region`                         | `string`       | Región donde se creará la VM        | `"us-central1"`                | ❌        |
| `zone`                           | `string`       | Zona donde se creará la VM          | `"us-central1-a"`              | ❌        |
| `instance_name`                  | `string`       | Nombre de la instancia VM           | -                              | ✅        |
| `machine_type`                   | `string`       | Tipo de máquina                     | `"e2-medium"`                  | ❌        |
| `vm_subnet_name`                 | `string`       | Nombre de la subnet                 | -                              | ✅        |
| `service_account_email`          | `string`       | Service Account para la VM          | -                              | ✅        |
| `boot_disk_size`                 | `number`       | Tamaño del disco (GB)               | `20`                           | ❌        |
| `enable_public_ip`               | `bool`         | Habilitar IP pública                | `false`                        | ❌        |
| `static_public_ip`               | `string`       | Nombre para IP pública estática     | `null`                         | ❌        |
| `use_ubuntu_image`               | `bool`         | Usar imagen Ubuntu                  | `false`                        | ❌        |
| `install_docker_compose`         | `bool`         | Instalar Docker Compose             | `true`                         | ❌        |
| `docker_compose_version`         | `string`       | Versión de Docker Compose           | `"v2.33.0"`                    | ❌        |
| `install_certbot`                | `bool`         | Instalar Certbot                    | `false`                        | ❌        |
| `metadata_startup_script`        | `string`       | Script de inicio personalizado      | `""`                           | ❌        |
| `deployment_scripts`             | `string`       | Ruta local a scripts de despliegue  | `""`                           | ❌        |
| `deployment_scripts_destination` | `string`       | Directorio destino en VM            | `"/home/ubuntu/configuration"` | ❌        |
| `microservices`                  | `list(object)` | Lista de microservicios a desplegar | `[]`                           | ❌        |
| `environment`                    | `string`       | Ambiente de despliegue              | `"dev"`                        | ❌        |

### Estructura de `microservices`

```hcl
microservices = [
  {
    name     = "api"
    repo_url = "https://github.com/user/api.git"
    branch   = "main"
    env_file = "envs/api.env"  # Ruta relativa o contenido del archivo .env
  }
]
```

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

## 📝 Ejemplo de Uso

### Configuración Básica con Docker Hub

```hcl
module "vm_docker" {
  source = "../../modules/vm-docker"

  project_id           = "my-project-id"
  region               = "us-central1"
  zone                 = "us-central1-a"
  instance_name        = "docker-vm"
  vm_subnet_name       = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"

  enable_public_ip     = true
  tags                 = ["allow-http"]
}
```

### Con Script de Despliegue Personalizado

```hcl
module "vm_docker" {
  source = "../../modules/vm-docker"

  project_id           = "my-project-id"
  region               = "us-central1"
  zone                 = "us-central1-a"
  instance_name        = "docker-vm"
  vm_subnet_name       = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"

  enable_public_ip              = true
  use_ubuntu_image              = true
  deployment_scripts            = "./scripts/deploy"
  deployment_scripts_destination = "/home/ubuntu/deployment"

  tags = ["allow-http"]
}
```

### Con Microservicios desde Git

```hcl
module "vm_docker" {
  source = "../../modules/vm-docker"

  project_id           = "my-project-id"
  region               = "us-central1"
  zone                 = "us-central1-a"
  instance_name        = "docker-vm"
  vm_subnet_name       = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"

  enable_public_ip = true
  use_ubuntu_image = true

  microservices = [
    {
      name     = "api"
      repo_url = "https://github.com/user/api.git"
      branch   = "main"
      env_file = "envs/api.env"
    },
    {
      name     = "worker"
      repo_url = "https://github.com/user/worker.git"
      branch   = "develop"
      env_file = "envs/worker.env"
    }
  ]

  tags = ["allow-http"]
}
```

### Con Certbot para SSL

```hcl
module "vm_docker" {
  source = "../../modules/vm-docker"

  project_id           = "my-project-id"
  region               = "us-central1"
  zone                 = "us-central1-a"
  instance_name        = "docker-vm"
  vm_subnet_name       = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"

  enable_public_ip  = true
  install_certbot   = true
  use_ubuntu_image  = true

  tags = ["allow-http", "allow-https"]
}
```

## 🔗 Dependencias

Este módulo requiere:

- **Subnet**: La subnet especificada en `vm_subnet_name` debe existir (normalmente creada por el módulo `network` de `shared-infra`)
- **Service Account**: El Service Account especificado en `service_account_email` debe existir (normalmente creado por el módulo `security` de `shared-infra`)
- **Firewall Rules**: Si se expone HTTP/HTTPS, las reglas de firewall correspondientes deben existir en `shared-infra`

## 📚 Scripts Incluidos

El módulo incluye scripts automáticos:

- **`docker_install.sh`**: Instala Docker y Docker Compose
- **`certbot_install.sh`**: Instala Certbot (si está habilitado)
- **`microservices_deploy.sh`**: Despliega microservicios desde repositorios Git

## ⚠️ Notas Importantes

1. **Imagen Base**: Por defecto usa Container-Optimized OS. Si `use_ubuntu_image = true`, usa Ubuntu 22.04 LTS.
2. **Docker Compose**: Se instala automáticamente si `install_docker_compose = true`.
3. **Microservicios**: Los microservicios se clonan desde Git y se despliegan usando Docker Compose. Requieren archivos `docker-compose.yml` en cada repositorio.
4. **Environment Files**: Los archivos `.env` para microservicios pueden ser rutas relativas o contenido directo.
5. **Scripts de Despliegue**: Si se especifica `deployment_scripts`, los scripts se copian a la VM y se ejecutan en el startup.

## 🔒 Seguridad

- La VM usa un Service Account con permisos mínimos
- Las claves SSH y variables de entorno se configuran mediante metadata (sensitive)
- Los scripts de despliegue se ejecutan con los permisos del usuario configurado

---

**Última actualización**: 2025-01-07
