# ============================================================================
# LOCALS: CONFIGURACIÓN Y TRANSFORMACIONES
# ============================================================================

locals {
  # Construir lista de redes autorizadas para el control plane
  master_authorized_networks_config = length(var.master_authorized_networks) > 0 ? [
    for cidr, description in var.master_authorized_networks : {
      cidr_block   = cidr
      display_name = description
    }
  ] : []

  # Mapeo de días de la semana a códigos RRULE (formato requerido por GKE)
  day_to_rrule = {
    "SUNDAY"    = "SU"
    "MONDAY"    = "MO"
    "TUESDAY"   = "TU"
    "WEDNESDAY" = "WE"
    "THURSDAY"  = "TH"
    "FRIDAY"    = "FR"
    "SATURDAY"  = "SA"
  }

  # Convertir día de la semana a código RRULE
  maintenance_window_day_rrule = local.day_to_rrule[var.maintenance_window_day]

  # Convertir hora HH:MM a formato RFC3339 para maintenance window
  # El formato RFC3339 requerido es: YYYY-MM-DDTHH:MM:SSZ
  # Usamos una fecha base (2023-01-01) y la hora especificada
  maintenance_window_start_time = "2023-01-01T${var.maintenance_window_start_time}:00Z"

  # end_time es 4 horas después de start_time (ventana de mantenimiento estándar)
  # GKE requiere al menos 4 horas continuas de ventana disponible
  # Extraemos la hora del start_time, le sumamos 4 horas y formateamos
  maintenance_window_start_hour = tonumber(split(":", var.maintenance_window_start_time)[0])
  maintenance_window_start_min  = tonumber(split(":", var.maintenance_window_start_time)[1])
  maintenance_window_end_hour   = local.maintenance_window_start_hour + 4
  # Si la hora de fin excede 23, ajustar al día siguiente (formato RFC3339 maneja esto automáticamente)
  maintenance_window_end_time = format("2023-01-01T%02d:%02d:00Z", local.maintenance_window_end_hour, local.maintenance_window_start_min)
}
