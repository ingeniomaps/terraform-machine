variable "project_id" {
  description = "ID del proyecto GCP"
  type        = string
}

variable "region" {
  description = "Región donde se creará el cluster GKE"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "Nombre del cluster GKE"
  type        = string
}

variable "gke_subnet_name" {
  description = "Nombre de la subnet GKE (obtenido de shared-infra). Puede ser null si GKE no está habilitado."
  type        = string
  default     = null
}

variable "gke_pods_range_name" {
  description = "Nombre del secondary range para pods (obtenido de shared-infra). Puede ser null si GKE no está habilitado."
  type        = string
  default     = null
}

variable "gke_services_range_name" {
  description = "Nombre del secondary range para services (obtenido de shared-infra). Puede ser null si GKE no está habilitado."
  type        = string
  default     = null
}

variable "gke_master_cidr" {
  description = "CIDR para el control plane de GKE (obtenido de shared-infra). Debe ser un CIDR /28."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/28$", var.gke_master_cidr))
    error_message = "gke_master_cidr debe ser un CIDR válido con máscara /28 (ej: 172.16.0.0/28)"
  }
}

variable "node_pool_name" {
  description = "Nombre del node pool"
  type        = string
  default     = "default-pool"
}

variable "node_machine_type" {
  description = "Tipo de máquina para los nodos"
  type        = string
  default     = "e2-medium"
}

variable "node_disk_size" {
  description = "Tamaño del disco de los nodos en GB"
  type        = number
  default     = 50
}

variable "node_disk_type" {
  description = "Tipo de disco de los nodos (pd-standard, pd-ssd)"
  type        = string
  default     = "pd-standard"

  validation {
    condition     = contains(["pd-standard", "pd-ssd"], var.node_disk_type)
    error_message = "node_disk_type debe ser: pd-standard o pd-ssd"
  }
}

variable "min_node_count" {
  description = "Número mínimo de nodos"
  type        = number
  default     = 1

  validation {
    condition     = var.min_node_count >= 0
    error_message = "min_node_count debe ser mayor o igual a 0"
  }
}

variable "max_node_count" {
  description = "Número máximo de nodos"
  type        = number
  default     = 3

  validation {
    condition     = var.max_node_count >= 1
    error_message = "max_node_count debe ser mayor o igual a 1"
  }
}

variable "initial_node_count" {
  description = "Número inicial de nodos"
  type        = number
  default     = 1

  validation {
    condition     = var.initial_node_count >= 0
    error_message = "initial_node_count debe ser mayor o igual a 0"
  }
}

variable "enable_autoscaling" {
  description = "Habilitar auto-scaling"
  type        = bool
  default     = true
}

variable "enable_autorepair" {
  description = "Habilitar auto-repair de nodos"
  type        = bool
  default     = true
}

variable "enable_autoupgrade" {
  description = "Habilitar auto-upgrade de nodos"
  type        = bool
  default     = true
}

variable "service_account_email" {
  description = "Email de la Service Account para los nodos (obtenido de shared-infra). Puede ser null y se asignará automáticamente."
  type        = string
  default     = null
}

variable "workload_identity_pool" {
  description = "Workload Identity Pool (obtenido de shared-infra, opcional). Si está vacío, se usa el pool por defecto del proyecto."
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "Versión de Kubernetes (dejar vacío para usar la última estable)"
  type        = string
  default     = ""
}

variable "enable_private_nodes" {
  description = "Usar nodos privados (sin IP pública)"
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "Habilitar endpoint privado del control plane"
  type        = bool
  default     = false
}

variable "master_authorized_networks" {
  description = "Redes autorizadas para acceder al control plane (formato: cidr:descripción)"
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels para el cluster y nodos"
  type        = map(string)
  default     = {}
}

variable "network_tags" {
  description = "Network tags para los nodos"
  type        = list(string)
  default     = []
}

variable "enable_http_load_balancing" {
  description = "Habilitar HTTP Load Balancing"
  type        = bool
  default     = true
}

variable "enable_horizontal_pod_autoscaling" {
  description = "Habilitar Horizontal Pod Autoscaling"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Habilitar Network Policy"
  type        = bool
  default     = false
}

variable "maintenance_window_start_time" {
  description = "Inicio de la ventana de mantenimiento (formato: HH:MM, ej: 02:00)"
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window_start_time))
    error_message = "maintenance_window_start_time debe estar en formato HH:MM (ej: 02:00)"
  }
}

variable "maintenance_window_day" {
  description = "Día de la ventana de mantenimiento (SUNDAY, MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY)"
  type        = string
  default     = "SUNDAY"

  validation {
    condition = contains([
      "SUNDAY",
      "MONDAY",
      "TUESDAY",
      "WEDNESDAY",
      "THURSDAY",
      "FRIDAY",
      "SATURDAY"
    ], var.maintenance_window_day)
    error_message = "maintenance_window_day debe ser uno de: SUNDAY, MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY"
  }
}

variable "deletion_protection" {
  description = "Habilitar protección contra eliminación del cluster. IMPORTANTE: Debe ser false para poder destruir el cluster."
  type        = bool
  default     = true
}
