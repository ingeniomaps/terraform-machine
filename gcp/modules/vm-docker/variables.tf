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

variable "metadata_startup_script" {
  description = "Script de inicio personalizado (opcional)"
  type        = string
  default     = ""
}

variable "ssh_keys" {
  description = "Claves SSH públicas para acceso (formato: usuario:clave)"
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "install_docker_compose" {
  description = "Instalar Docker Compose"
  type        = bool
  default     = true
}

variable "docker_compose_version" {
  description = "Versión de Docker Compose a instalar"
  type        = string
  default     = "v2.33.0"
}

variable "install_certbot" {
  description = "Instalar Certbot para certificados SSL"
  type        = bool
  default     = false
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

variable "deployment_scripts" {
  description = <<-EOT
    Ruta local a scripts o archivos de despliegue a copiar a la VM.

    Útil para archivos grandes que exceden el límite de metadata (256KB),
    múltiples archivos, o directorios completos.

    Requiere gcloud CLI instalado y autenticado localmente, y que la VM
    tenga el tag "allow-iap-ssh" para conexiones vía IAP.

    Para scripts pequeños (< 256KB), considera usar `metadata_startup_script`.
    Para microservicios, usa la variable `microservices`.
  EOT
  type        = string
  default     = ""
}

variable "deployment_scripts_destination" {
  description = <<-EOT
    Directorio destino en la VM donde se copiarán los scripts de despliegue.

    Solo se usa si `deployment_scripts` está especificado.
    Los archivos se copian recursivamente desde el directorio origen
    al directorio destino especificado.
  EOT
  type        = string
  default     = "/home/ubuntu/configuration"
}

variable "microservices" {
  description = "Lista de microservicios a desplegar (repositorios GitHub)"
  type = list(object({
    name           = string
    repo_url       = string
    branch         = string
    env_file       = string  # Contenido del archivo .env o ruta relativa a un archivo .env (ej: "envs/local-deps.env")
    env_file_name  = optional(string, ".env") # Nombre del archivo env en el repo (ej: ".env.local")
    launch_command = string  # (Obligatorio) Comando personalizado para lanzar el microservicio, puede ser null.
  }))
  default = []
}

# Variable 'environment' no se usa actualmente en el módulo
# Se mantiene para compatibilidad futura o uso en scripts personalizados
variable "environment" {
  description = "Ambiente de despliegue (dev, qa, stg, prod). Actualmente no se usa en el módulo, se mantiene para compatibilidad."
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "qa", "stg", "prod"], var.environment)
    error_message = "environment debe ser dev, qa, stg o prod"
  }
}
