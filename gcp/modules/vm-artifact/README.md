# Módulo VM Artifact

Este módulo crea una instancia de Compute Engine (VM) configurada para ejecutar contenedores Docker desde Google Artifact Registry.

## 📋 Descripción

El módulo `vm-artifact` extiende `vm-base` y agrega:

- **Instalación de Docker**: Instala Docker automáticamente
- **Autenticación con Artifact Registry**: Configura autenticación para pull de imágenes
- **Despliegue Automático**: Despliega automáticamente un contenedor Docker desde Artifact Registry al iniciar
- **Health Checks**: Script de verificación de salud del contenedor
- **Actualización de Imágenes**: Soporte para actualizar imágenes sin reiniciar la VM

## 🔧 Variables Principales

| Variable                | Tipo          | Descripción                                         | Default           | Requerido |
| ----------------------- | ------------- | --------------------------------------------------- | ----------------- | --------- |
| `project_id`            | `string`      | ID del proyecto GCP                                 | -                 | ✅        |
| `region`                | `string`      | Región donde se creará la VM                        | `"us-central1"`   | ❌        |
| `zone`                  | `string`      | Zona donde se creará la VM                          | `"us-central1-a"` | ❌        |
| `instance_name`         | `string`      | Nombre de la instancia VM                           | -                 | ✅        |
| `machine_type`          | `string`      | Tipo de máquina                                     | `"e2-medium"`     | ❌        |
| `vm_subnet_name`        | `string`      | Nombre de la subnet                                 | -                 | ✅        |
| `service_account_email` | `string`      | Service Account para la VM                          | -                 | ✅        |
| `artifact_registry_url` | `string`      | URL completa del Artifact Registry                  | -                 | ✅        |
| `docker_image`          | `string`      | Imagen Docker a ejecutar (nombre:tag)               | -                 | ✅        |
| `container_port`        | `number`      | Puerto del contenedor                               | `8080`            | ❌        |
| `host_port`             | `number`      | Puerto del host                                     | `8080`            | ❌        |
| `docker_env_vars`       | `map(string)` | Variables de entorno para el contenedor             | `{}`              | ❌        |
| `docker_command`        | `string`      | Comando personalizado para el contenedor            | `""`              | ❌        |
| `restart_policy`        | `string`      | Política de reinicio (always, unless-stopped, etc.) | `"always"`        | ❌        |
| `boot_disk_size`        | `number`      | Tamaño del disco (GB)                               | `20`              | ❌        |
| `enable_public_ip`      | `bool`        | Habilitar IP pública                                | `false`           | ❌        |
| `static_public_ip`      | `string`      | Nombre para IP pública estática                     | `null`            | ❌        |
| `health_check_path`     | `string`      | Ruta para health check HTTP                         | `""`              | ❌        |
| `health_check_port`     | `number`      | Puerto para health check (0 = usar container_port)  | `0`               | ❌        |
| `use_ubuntu_image`      | `bool`        | Usar imagen Ubuntu                                  | `false`           | ❌        |

## 📤 Outputs

| Output                  | Descripción                                          |
| ----------------------- | ---------------------------------------------------- |
| `instance_id`           | ID de la instancia VM                                |
| `instance_name`         | Nombre de la instancia                               |
| `instance_zone`         | Zona de la instancia                                 |
| `internal_ip`           | IP interna de la instancia                           |
| `external_ip`           | IP externa (null si no tiene IP pública)             |
| `static_public_ip_name` | Nombre del recurso de IP pública estática            |
| `docker_image_path`     | Ruta completa de la imagen Docker                    |
| `container_url`         | URL para acceder al contenedor (si tiene IP pública) |
| `ssh_command`           | Comando SSH para conectarse vía IAP                  |
| `self_link`             | Self link de la instancia                            |

## 📝 Ejemplo de Uso

### Configuración Básica

```hcl
module "vm_artifact" {
  source = "../../modules/vm-artifact"

  project_id           = "my-project-id"
  region               = "us-central1"
  zone                 = "us-central1-a"
  instance_name        = "artifact-vm"
  vm_subnet_name       = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"

  artifact_registry_url = "us-central1-docker.pkg.dev/my-project/docker-images"
  docker_image          = "hello-world:1.0.0"
  container_port        = 80
  host_port             = 80

  enable_public_ip = true
  tags             = ["allow-http-direct"]
}
```

### Con Variables de Entorno

```hcl
module "vm_artifact" {
  source = "../../modules/vm-artifact"

  project_id           = "my-project-id"
  region               = "us-central1"
  zone                 = "us-central1-a"
  instance_name        = "artifact-vm"
  vm_subnet_name       = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"

  artifact_registry_url = "us-central1-docker.pkg.dev/my-project/docker-images"
  docker_image          = "my-app:latest"
  container_port        = 8080
  host_port             = 8080

  docker_env_vars = {
    ENV          = "production"
    DATABASE_URL = "postgresql://..."
    API_KEY      = "secret-key"
  }

  enable_public_ip = true
  tags             = ["allow-http-direct"]
}
```

### Con Health Check

```hcl
module "vm_artifact" {
  source = "../../modules/vm-artifact"

  project_id           = "my-project-id"
  region               = "us-central1"
  zone                 = "us-central1-a"
  instance_name        = "artifact-vm"
  vm_subnet_name       = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"

  artifact_registry_url = "us-central1-docker.pkg.dev/my-project/docker-images"
  docker_image          = "my-app:1.0.0"
  container_port        = 8080
  host_port             = 8080

  health_check_path = "/health"
  health_check_port = 8080

  enable_public_ip = true
  tags             = ["allow-http-direct"]
}
```

### Con Comando Personalizado

```hcl
module "vm_artifact" {
  source = "../../modules/vm-artifact"

  project_id           = "my-project-id"
  region               = "us-central1"
  zone                 = "us-central1-a"
  instance_name        = "artifact-vm"
  vm_subnet_name       = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"

  artifact_registry_url = "us-central1-docker.pkg.dev/my-project/docker-images"
  docker_image          = "my-app:1.0.0"
  container_port        = 8080
  host_port             = 8080

  docker_command = "node server.js --port 8080"

  enable_public_ip = true
  tags             = ["allow-http-direct"]
}
```

## 🔗 Dependencias

Este módulo requiere:

- **Subnet**: La subnet especificada en `vm_subnet_name` debe existir (normalmente creada por el módulo `network` de `shared-infra`)
- **Service Account**: El Service Account especificado en `service_account_email` debe existir y tener permisos de lectura en Artifact Registry (normalmente creado por el módulo `security` de `shared-infra`)
- **Artifact Registry**: El repositorio especificado en `artifact_registry_url` debe existir (normalmente creado por el módulo `artifact_registry` de `shared-infra`)
- **Firewall Rules**: Si se expone HTTP, las reglas de firewall correspondientes deben existir en `shared-infra`

## 📚 Scripts Incluidos

El módulo incluye scripts automáticos:

- **`docker_install.sh`**: Instala Docker
- **`artifact_deploy.sh`**: Autentica con Artifact Registry y despliega el contenedor
- **`health_check.sh`**: Verifica la salud del contenedor

## ⚠️ Notas Importantes

1. **Imagen Base**: Por defecto usa Container-Optimized OS. Si `use_ubuntu_image = true`, usa Ubuntu 22.04 LTS.
2. **Autenticación**: La autenticación con Artifact Registry se hace automáticamente usando el Service Account de la VM.
3. **Tags Inmutables**: Artifact Registry tiene tags inmutables por defecto. Para actualizar una imagen, usa un nuevo tag.
4. **Actualización de Imágenes**: Para actualizar la imagen sin reiniciar la VM, cambia `docker_image` en `terraform.tfvars` y ejecuta `terraform apply`. Luego, actualiza el contenedor manualmente vía SSH o usa el script `switch-version.sh` del ejemplo.
5. **Health Check**: Si se especifica `health_check_path`, el script verifica periódicamente que el contenedor responda correctamente.

## 🔒 Seguridad

- La VM usa un Service Account con permisos de lectura en Artifact Registry
- Las variables de entorno sensibles se configuran mediante metadata (sensitive)
- El acceso a Artifact Registry se autentica automáticamente usando el Service Account

## 🔄 Actualización de Imágenes

Para actualizar la imagen Docker:

1. **Cambiar tag en terraform.tfvars**:

   ```hcl
   docker_image = "my-app:1.0.1"
   ```

2. **Aplicar cambios**:

   ```bash
   terraform apply
   ```

3. **Actualizar contenedor en la VM** (opcional, si no se reinicia automáticamente):

   ```bash
   # Conectar vía SSH
   gcloud compute ssh my-vm --zone=us-central1-a --tunnel-through-iap

   # Detener contenedor actual
   sudo docker stop my-container

   # Pull nueva imagen
   sudo docker pull us-central1-docker.pkg.dev/my-project/docker-images/my-app:1.0.1

   # Iniciar nuevo contenedor
   sudo docker run -d --name my-container -p 8080:8080 \
     us-central1-docker.pkg.dev/my-project/docker-images/my-app:1.0.1
   ```

---

**Última actualización**: 2025-01-07
