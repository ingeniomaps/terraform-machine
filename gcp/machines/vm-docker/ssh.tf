# ============================================================================
# GENERACIÓN DE CLAVES SSH
# ============================================================================
# Generar par de claves SSH usando Terraform (declarativo y reproducible)
# Mejor práctica: usar Terraform en lugar de ssh-keygen

resource "tls_private_key" "vm_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Guardar clave privada en archivo .pem (protegido por .gitignore)
resource "local_file" "private_key" {
  content         = tls_private_key.vm_ssh_key.private_key_pem
  filename        = "${path.module}/keys/${var.instance_name}.pem"
  file_permission = "0600"

  depends_on = [tls_private_key.vm_ssh_key]
}

# Guardar clave pública en archivo .pub (opcional, para referencia)
resource "local_file" "public_key" {
  content         = tls_private_key.vm_ssh_key.public_key_openssh
  filename        = "${path.module}/keys/${var.instance_name}.pub"
  file_permission = "0644"

  depends_on = [tls_private_key.vm_ssh_key]
}

# ============================================================================
# REGLAS DE FIREWALL PARA SSH
# ============================================================================
# Las reglas de firewall para SSH están gestionadas por la infraestructura
# compartida en ./terraform/gcp/shared-infra/modules/network/firewall/allow.tf
#
# Los tags se construyen automáticamente con el formato: "${network_name}-allow-iap-ssh"
# donde network_name se obtiene recursivamente desde shared-infra (formato: workspace-env)
#
# 1. SSH vía IAP (recomendado, más seguro):
#    - Tag requerido: "${network_name}-allow-iap-ssh" (se agrega automáticamente a todas las VMs)
#    - También acepta el tag corto "allow-iap-ssh" que se expande automáticamente
#    - Permite SSH solo desde el rango IAP (35.235.240.0/20)
#
# 2. SSH directo desde Internet (opcional, menos seguro):
#    - Tag requerido: "${network_name}-allow-ssh" (debe agregarse manualmente si se necesita)
#    - También acepta el tag corto "allow-ssh" que se expande automáticamente
#    - Permite SSH desde cualquier IP (0.0.0.0/0)
#    - ⚠️ ADVERTENCIA: Solo usar en desarrollo/testing. Para producción, usar IAP.
#
# Para habilitar SSH directo, agrega el tag en terraform.tfvars:
#   tags = ["allow-ssh"]  # Se expandirá automáticamente a "${network_name}-allow-ssh"
#   # O usa el tag completo:
#   tags = ["workspace-dev-allow-ssh"]
