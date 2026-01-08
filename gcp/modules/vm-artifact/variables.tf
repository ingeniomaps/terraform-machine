variable "project_id" {
  description = "ID del proyecto GCP"
  type        = string
}

variable "region" {
  description = "Región donde se creará la VM"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona donde se creará la VM"
  type        = string
  default     = "us-central1-a"
}

variable "instance_name" {
  description = "Nombre de la instancia VM"
  type        = string

  validation {
    condition     = length(var.instance_name) >= 1 && length(var.instance_name) <= 63 && can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.instance_name))
    error_message = "instance_name debe tener entre 1 y 63 caracteres, empezar con letra minúscula, y contener solo letras minúsculas, números y guiones"
  }
}

variable "machine_type" {
  description = "Tipo de máquina (ej: e2-medium, n1-standard-1)"
  type        = string
  default     = "e2-medium"
}

variable "vm_subnet_name" {
  description = "Nombre de la subnet (obtenido de shared-infra)"
  type        = string
}

variable "service_account_email" {
  description = "Email de la Service Account para la VM (obtenido de shared-infra)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.service_account_email))
    error_message = "service_account_email debe ser un email válido (ej: sa@project.iam.gserviceaccount.com)"
  }
}

variable "artifact_registry_url" {
  description = "URL completa del Artifact Registry (obtenido de shared-infra). Formato: REGION-docker.pkg.dev/PROJECT_ID/REPO_NAME"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.docker\\.pkg\\.dev/[a-z0-9-]+/[a-z0-9-]+$", var.artifact_registry_url))
    error_message = "artifact_registry_url debe tener formato: REGION-docker.pkg.dev/PROJECT_ID/REPO_NAME"
  }
}

variable "docker_image" {
  description = "Imagen Docker a ejecutar (formato: nombre-imagen:tag)"
  type        = string
}

variable "docker_image_full_path" {
  description = "Ruta completa de la imagen Docker (se construye automáticamente si no se especifica)"
  type        = string
  default     = ""
}

variable "container_port" {
  description = "Puerto del contenedor"
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port debe estar entre 1 y 65535"
  }
}

variable "host_port" {
  description = "Puerto del host (mismo que container_port por defecto)"
  type        = number
  default     = 8080

  validation {
    condition     = var.host_port > 0 && var.host_port <= 65535
    error_message = "host_port debe estar entre 1 y 65535"
  }
}

variable "docker_env_vars" {
  description = "Variables de entorno para el contenedor Docker"
  type        = map(string)
  default     = {}
}

variable "docker_command" {
  description = "Comando personalizado para ejecutar el contenedor (opcional)"
  type        = string
  default     = ""
}

variable "restart_policy" {
  description = "Política de reinicio del contenedor (always, unless-stopped, on-failure, no)"
  type        = string
  default     = "always"
  validation {
    condition     = contains(["always", "unless-stopped", "on-failure", "no"], var.restart_policy)
    error_message = "restart_policy debe ser: always, unless-stopped, on-failure o no"
  }
}

variable "tags" {
  description = "Network tags para la VM"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels para la VM"
  type        = map(string)
  default     = {}
}

variable "boot_disk_size" {
  description = "Tamaño del disco de arranque en GB"
  type        = number
  default     = 20

  validation {
    condition     = var.boot_disk_size >= 10 && var.boot_disk_size <= 65536
    error_message = "boot_disk_size debe estar entre 10 GB y 65536 GB (64 TB)"
  }
}

variable "boot_disk_type" {
  description = "Tipo de disco de arranque (pd-standard, pd-ssd)"
  type        = string
  default     = "pd-standard"
}

variable "enable_public_ip" {
  description = "Habilitar IP pública (requiere Cloud NAT si es false)"
  type        = bool
  default     = false
}

variable "static_public_ip" {
  description = "Crear y usar una IP pública estática. Si se especifica un nombre, se crea una nueva IP estática. Si es null, usa IP ephemeral."
  type        = string
  default     = null
}

variable "static_internal_ip" {
  description = "IP interna estática a asignar (debe estar en el rango de la subnet). Si es null, se asigna automáticamente."
  type        = string
  default     = null
}

variable "use_ubuntu_image" {
  description = "Usar imagen Ubuntu en lugar de Container-Optimized OS"
  type        = bool
  default     = false
}

variable "ubuntu_image_family" {
  description = "Familia de imagen Ubuntu (si use_ubuntu_image = true)"
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "health_check_path" {
  description = "Ruta para health check HTTP (opcional)"
  type        = string
  default     = ""
}

variable "health_check_port" {
  description = "Puerto para health check (usa container_port si no se especifica)"
  type        = number
  default     = 0
}
