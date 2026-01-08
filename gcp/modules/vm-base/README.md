# Módulo VM Base

Este módulo crea una instancia de Compute Engine (VM) básica en GCP. Es el módulo base que utilizan `vm-docker` y `vm-artifact` para crear VMs especializadas.

## 📋 Descripción

El módulo `vm-base` crea:

- **Instancia VM**: Instancia de Compute Engine con configuración básica
- **Disco de Arranque**: Disco persistente con tamaño y tipo configurable
- **IP Pública Estática** (opcional): IP pública estática si se especifica `static_public_ip`
- **IP Interna Estática** (opcional): IP interna estática si se especifica `static_internal_ip`
- **Metadata**: Scripts de inicio y claves SSH configurables

## 🔧 Variables Principales

| Variable                | Tipo           | Descripción                           | Default           | Requerido |
| ----------------------- | -------------- | ------------------------------------- | ----------------- | --------- |
| `project_id`            | `string`       | ID del proyecto GCP                   | -                 | ✅        |
| `region`                | `string`       | Región donde se creará la VM          | `"us-central1"`   | ❌        |
| `zone`                  | `string`       | Zona donde se creará la VM            | `"us-central1-a"` | ❌        |
| `instance_name`         | `string`       | Nombre de la instancia VM             | -                 | ✅        |
| `machine_type`          | `string`       | Tipo de máquina (ej: e2-medium)       | `"e2-medium"`     | ❌        |
| `vm_subnet_name`        | `string`       | Nombre de la subnet (de shared-infra) | -                 | ✅        |
| `service_account_email` | `string`       | Service Account para la VM            | -                 | ✅        |
| `tags`                  | `list(string)` | Network tags para la VM               | `[]`              | ❌        |
| `labels`                | `map(string)`  | Labels para la VM                     | `{}`              | ❌        |
| `boot_disk_size`        | `number`       | Tamaño del disco de arranque (GB)     | `20`              | ❌        |
| `boot_disk_type`        | `string`       | Tipo de disco (pd-standard, pd-ssd)   | `"pd-standard"`   | ❌        |
| `enable_public_ip`      | `bool`         | Habilitar IP pública                  | `false`           | ❌        |
| `static_public_ip`      | `string`       | Nombre para IP pública estática       | `null`            | ❌        |
| `static_internal_ip`    | `string`       | IP interna estática                   | `null`            | ❌        |
| `vm_image`              | `string`       | Imagen de la VM (formato GCP)         | -                 | ✅        |
| `startup_script`        | `string`       | Script de inicio personalizado        | `""`              | ❌        |
| `ssh_keys`              | `list(string)` | Claves SSH públicas                   | `[]`              | ❌        |
| `purpose_label`         | `string`       | Valor del label 'purpose'             | `"vm"`            | ❌        |

## 📤 Outputs

| Output                  | Descripción                               |
| ----------------------- | ----------------------------------------- |
| `instance_id`           | ID de la instancia                        |
| `instance_name`         | Nombre de la instancia                    |
| `instance_zone`         | Zona de la instancia                      |
| `internal_ip`           | IP interna de la instancia                |
| `external_ip`           | IP externa (null si no tiene IP pública)  |
| `static_public_ip_name` | Nombre del recurso de IP pública estática |
| `ssh_command`           | Comando SSH para conectarse vía IAP       |
| `self_link`             | Self link de la instancia                 |

## 📝 Ejemplo de Uso

### Configuración Básica

```hcl
module "vm_base" {
  source = "../../modules/vm-base"

  project_id           = "my-project-id"
  region               = "us-central1"
  zone                 = "us-central1-a"
  instance_name        = "my-vm"
  machine_type         = "e2-medium"
  vm_subnet_name       = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"
  vm_image             = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"

  tags = ["allow-ssh"]
  labels = {
    env = "dev"
  }
}
```

### Con IP Pública Estática

```hcl
module "vm_base" {
  source = "../../modules/vm-base"

  project_id           = "my-project-id"
  region               = "us-central1"
  zone                 = "us-central1-a"
  instance_name        = "my-vm"
  machine_type         = "e2-medium"
  vm_subnet_name       = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"
  vm_image             = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"

  enable_public_ip      = true
  static_public_ip     = "my-vm-static-ip"

  tags = ["allow-ssh", "allow-http"]
}
```

### Con Script de Inicio

```hcl
module "vm_base" {
  source = "../../modules/vm-base"

  project_id           = "my-project-id"
  region               = "us-central1"
  zone                 = "us-central1-a"
  instance_name        = "my-vm"
  machine_type         = "e2-medium"
  vm_subnet_name       = "workspace-dev-vpc-vm-subnet"
  service_account_email = "vm-reader@my-project.iam.gserviceaccount.com"
  vm_image             = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"

  startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    systemctl start nginx
  EOF
}
```

## 🔗 Dependencias

Este módulo requiere:

- **Subnet**: La subnet especificada en `vm_subnet_name` debe existir (normalmente creada por el módulo `network` de `shared-infra`)
- **Service Account**: El Service Account especificado en `service_account_email` debe existir (normalmente creado por el módulo `security` de `shared-infra`)

## 📚 Uso por Módulos Especializados

Este módulo es utilizado internamente por:

- **`vm-docker`**: Extiende `vm-base` para desplegar contenedores Docker desde Docker Hub o scripts personalizados
- **`vm-artifact`**: Extiende `vm-base` para desplegar contenedores Docker desde Artifact Registry

## ⚠️ Notas Importantes

1. **IP Pública**: Si `enable_public_ip = false`, la VM solo tendrá IP interna. Para acceso saliente, requiere Cloud NAT.
2. **IP Estática**: Si se especifica `static_public_ip`, se crea una IP estática regional. Si se especifica `static_internal_ip`, debe estar en el rango de la subnet.
3. **SSH**: Si no hay IP pública, usa IAP (Identity-Aware Proxy) para conectarse. El output `ssh_command` proporciona el comando correcto.
4. **Imagen**: El formato completo de `vm_image` debe ser: `projects/{PROJECT}/global/images/{IMAGE}` o `projects/{PROJECT}/global/images/family/{FAMILY}`
5. **Network Tags**: Los tags se usan para reglas de firewall. Asegúrate de que las reglas correspondientes existan en `shared-infra`.

## 🔒 Seguridad

- La VM usa un Service Account con permisos mínimos necesarios
- Las claves SSH se configuran mediante metadata (sensitive)
- Si no hay IP pública, el acceso SSH requiere IAP

---

**Última actualización**: 2025-01-07
