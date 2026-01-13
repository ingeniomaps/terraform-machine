# ============================================================================
# LOCALS: Obtener valores desde remote_state o variables directas
# ============================================================================

locals {
  # Usar variables directas si están definidas, sino intentar desde remote_state
  vm_subnet_name = coalesce(
    var.vm_subnet_name,
    try(data.terraform_remote_state.shared_infra[0].outputs.vm_subnet_name, null)
  )

  vm_subnet_cidr = coalesce(
    var.vm_subnet_cidr,
    try(data.terraform_remote_state.shared_infra[0].outputs.vm_subnet_cidr, null)
  )

  vpc_name = coalesce(
    var.vpc_name,
    try(data.terraform_remote_state.shared_infra[0].outputs.vpc_name, null)
  )

  cloud_nat_name = try(
    data.terraform_remote_state.shared_infra[0].outputs.cloud_nat_name,
    null
  )

  # Obtener network_name desde shared-infra (formato: workspace-env)
  # Si no está disponible, derivarlo del vm_subnet_name (formato: network_name-vm-subnet)
  network_name = coalesce(
    var.network_name,
    try(data.terraform_remote_state.shared_infra[0].outputs.network_name, null),
    try(regex("^(.+)-vm-subnet$", local.vm_subnet_name)[0], null)
  )

  # Obtener tags de red desde shared-infra (recursivo y automático)
  network_tags = try(
    data.terraform_remote_state.shared_infra[0].outputs.network_tags,
    {
      allow_iap_ssh = local.network_name != null ? "${local.network_name}-allow-iap-ssh" : "allow-iap-ssh"
      allow_ssh     = local.network_name != null ? "${local.network_name}-allow-ssh" : "allow-ssh"
    }
  )

  service_account_email = coalesce(
    var.service_account_email,
    try(data.terraform_remote_state.shared_infra[0].outputs.vm_reader_email, null)
  )

  # Combinar claves SSH: la generada por Terraform + las proporcionadas manualmente
  # Formato: "usuario:clave_publica"
  ssh_keys_combined = concat(
    # Clave generada automáticamente por Terraform
    ["ubuntu:${tls_private_key.vm_ssh_key.public_key_openssh}"],
    # Claves adicionales proporcionadas manualmente en terraform.tfvars
    var.ssh_keys
  )

  # Normalizar tags del usuario: expandir tags cortos a formato completo
  # Si el usuario proporciona "allow-ssh" o "allow-iap-ssh", expandirlos con network_name
  normalized_user_tags = [
    for tag in var.tags : (
      tag == "allow-ssh" ? local.network_tags.allow_ssh : (
        tag == "allow-iap-ssh" ? local.network_tags.allow_iap_ssh : tag
      )
    )
  ]

  # Combinar tags: siempre incluir el tag de IAP desde network_tags + tags adicionales del usuario
  # El tag se obtiene recursivamente desde shared-infra (formato: network_name-allow-iap-ssh)
  # Usar distinct para evitar duplicados
  tags_combined = distinct(concat(
    # Tag requerido para SSH vía IAP (gestión automática, obtenido desde shared-infra)
    [local.network_tags.allow_iap_ssh],
    # Tags adicionales proporcionados manualmente en terraform.tfvars (ya normalizados)
    # Para SSH directo, el usuario puede agregar "allow-ssh" y se expandirá automáticamente
    local.normalized_user_tags
  ))
}
