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

variable "credentials_file" {
  description = "Nombre del archivo JSON de credenciales (opcional, debe estar en ../keys/). Si no se especifica, se usa GOOGLE_APPLICATION_CREDENTIALS o gcloud auth."
  type        = string
  default     = null
  sensitive   = true
}

variable "shared_infra_state_bucket" {
  description = "Bucket donde está el estado de la infraestructura compartida"
  type        = string
}

variable "shared_infra_state_prefix" {
  description = "Prefijo del estado de la infraestructura compartida (debe coincidir con el backend de shared-infra)"
  type        = string
}

variable "instance_name" {
  description = "Nombre de la instancia VM"
  type        = string
  default     = "vm-artifact-dev"
}

variable "machine_type" {
  description = "Tipo de máquina (ej: e2-medium, n1-standard-1)"
  type        = string
  default     = "e2-medium"
}

variable "docker_image" {
  description = "Imagen Docker a ejecutar (formato: nombre-imagen:tag)"
  type        = string
}

variable "container_port" {
  description = "Puerto del contenedor"
  type        = number
  default     = 8080
}

variable "host_port" {
  description = "Puerto del host"
  type        = number
  default     = 8080
}

variable "docker_env_vars" {
  description = "Variables de entorno para el contenedor"
  type        = map(string)
  default     = {}
}

variable "docker_command" {
  description = "Comando personalizado para ejecutar el contenedor (opcional)"
  type        = string
  default     = ""
}

variable "restart_policy" {
  description = "Política de reinicio (always, unless-stopped, on-failure, no)"
  type        = string
  default     = "always"
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
}

variable "boot_disk_type" {
  description = "Tipo de disco de arranque (pd-standard, pd-ssd)"
  type        = string
  default     = "pd-standard"
}

variable "enable_public_ip" {
  description = "Habilitar IP pública"
  type        = bool
  default     = false
}

variable "static_public_ip" {
  description = "Nombre para crear una IP pública estática. Si es null, usa IP ephemeral."
  type        = string
  default     = null
}

variable "static_internal_ip" {
  description = "IP interna estática a asignar (debe estar en el rango de la subnet). Si es null, se asigna automáticamente."
  type        = string
  default     = null
}

variable "health_check_path" {
  description = "Ruta para health check HTTP (opcional)"
  type        = string
  default     = ""
}

variable "health_check_port" {
  description = "Puerto para health check (usa container_port si es 0)"
  type        = number
  default     = 0
}

variable "use_ubuntu_image" {
  description = "Usar imagen Ubuntu en lugar de Container-Optimized OS"
  type        = bool
  default     = false
}
