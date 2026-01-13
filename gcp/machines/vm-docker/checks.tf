# ============================================================================
# VALIDACIONES
# ============================================================================
# Validación: al menos uno de los métodos debe proporcionar los valores
# (variables directas o remote_state)

check "required_values" {
  assert {
    condition     = local.vm_subnet_name != null
    error_message = "vm_subnet_name debe especificarse en terraform.tfvars (vm_subnet_name = \"...\") o via shared_infra_state_bucket/prefix"
  }

  assert {
    condition     = local.service_account_email != null
    error_message = "service_account_email debe especificarse en terraform.tfvars (service_account_email = \"...\") o via shared_infra_state_bucket/prefix"
  }
}

# Validación: Si se especifica static_internal_ip, se recomienda tener vm_subnet_cidr para documentación
# Nota: GCP validará automáticamente que la IP esté en el rango de la subnet al crear la VM
check "static_internal_ip_with_subnet_cidr" {
  assert {
    condition = (
      var.static_internal_ip == null ||
      local.vm_subnet_cidr != null ||
      var.vm_subnet_cidr != null
    )
    error_message = "Si especificas static_internal_ip, se recomienda proporcionar vm_subnet_cidr (via shared_infra_state_bucket/prefix o terraform.tfvars) para documentación. GCP validará automáticamente que la IP esté en el rango de la subnet."
  }
}
