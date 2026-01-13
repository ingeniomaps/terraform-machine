# ============================================================================
# VARIABLES COMUNES PARA VM BASE
# ============================================================================

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

variable "vm_image" {
  description = "Imagen de la VM (formato completo de GCP, ej: projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts)"
  type        = string
}

variable "startup_script" {
  description = "Script de inicio personalizado (será agregado a metadata)"
  type        = string
  default     = ""
}

variable "ssh_keys" {
  description = "Claves SSH públicas para acceso (formato: usuario:clave)"
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "purpose_label" {
  description = "Valor del label 'purpose' (ej: docker-vm, docker-container)"
  type        = string
  default     = "vm"
}

variable "additional_metadata" {
  description = "Metadata adicional para la VM (mapa de clave-valor)"
  type        = map(string)
  default     = {}
}
