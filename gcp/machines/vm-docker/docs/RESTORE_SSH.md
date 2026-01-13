# 🔑 Restaurar Clave SSH en la VM

Este documento explica cómo restaurar la clave SSH en la VM cuando se pierde el acceso.

## 📋 Cuándo usar este script

Usa `restore-ssh-key.sh` cuando:
- ✅ La clave SSH se borró de la VM
- ✅ La VM se actualizó y perdió las claves
- ✅ No puedes conectarte por SSH
- ✅ Necesitas restaurar el acceso rápidamente

## 🚀 Uso Rápido

```bash
cd machines/vm-docker
make restore-ssh
# O directamente:
./scripts/restore-ssh-key.sh
```

## 📝 Requisitos

1. **Terraform** instalado y configurado
2. **gcloud** instalado y autenticado
3. **IAP habilitado** en el proyecto (tag `allow-iap-ssh` en la VM)
4. **Permisos** para modificar metadata de la instancia

## 🔧 Qué hace el script

1. **Obtiene información** de la VM desde Terraform (nombre, zona, proyecto)
2. **Lee la clave pública** desde Terraform (output o archivo generado)
3. **Verifica el estado** de la VM (debe estar RUNNING)
4. **Agrega la clave** usando uno de estos métodos:
   - **Método 1 (preferido)**: Conecta vía IAP y agrega directamente a `~/.ssh/authorized_keys`
   - **Método 2 (alternativo)**: Agrega al metadata de la instancia usando `gcloud`

## 📖 Ejemplos de Uso

### Uso básico (automático)
```bash
./scripts/restore-ssh-key.sh
```

El script detecta automáticamente:
- Nombre de la instancia
- Zona
- Proyecto
- Clave pública SSH

### Verificar que funciona
```bash
# Después de ejecutar el script, verifica la conexión:
terraform output external_ip
ssh -i keys/$(terraform output -raw instance_name).pem ubuntu@<IP_PUBLICA>
```

## ⚠️ Solución de Problemas

### Error: "No se pudo obtener información desde outputs"
**Solución**: Ejecuta `terraform apply` primero para crear los outputs

### Error: "La VM no está en estado RUNNING"
**Solución**: Inicia la VM primero:
```bash
gcloud compute instances start <INSTANCE_NAME> --zone=<ZONE> --project=<PROJECT_ID>
```

### Error: "No se pudo conectar vía IAP"
**Causas posibles**:
1. La VM no tiene el tag `allow-iap-ssh`
2. IAP no está habilitado en el proyecto
3. No tienes permisos para usar IAP

**Soluciones**:
1. Agrega el tag: `gcloud compute instances add-tags <INSTANCE_NAME> --tags=allow-iap-ssh --zone=<ZONE>`
2. Habilita IAP: `gcloud services enable iap.googleapis.com --project=<PROJECT_ID>`
3. Verifica permisos IAM: `gcloud projects get-iam-policy <PROJECT_ID>`

### Error: "No se pudo obtener la clave pública SSH"
**Solución**: Ejecuta `terraform apply` para generar la clave:
```bash
terraform apply
```

## 🔄 Flujo Completo

```bash
# 1. Asegúrate de estar en el directorio correcto
cd machines/vm-docker

# 2. Verifica que Terraform está inicializado
terraform init

# 3. Ejecuta el script de restauración (usando Makefile)
make restore-ssh

# 4. Verifica la conexión
make ssh
```

## 📚 Métodos de Restauración

### Método 1: IAP + authorized_keys (Recomendado)
- ✅ Más confiable
- ✅ No afecta otras claves
- ✅ Funciona incluso si el metadata está corrupto
- ⚠️ Requiere IAP habilitado

### Método 2: Metadata de la instancia (Alternativo)
- ✅ Funciona sin IAP
- ✅ Aplica a todas las VMs con el mismo metadata
- ⚠️ Reemplaza todas las claves del metadata

## 🔒 Seguridad

- La clave privada está protegida por `.gitignore`
- El script solo agrega la clave, no la elimina
- Verifica que la clave no existe antes de agregarla (idempotente)

## 💡 Tips

1. **Guarda la clave privada**: Asegúrate de tener backup de `keys/<instance_name>.pem`
2. **Múltiples claves**: Puedes agregar claves adicionales en `terraform.tfvars`
3. **Logs**: El script muestra información detallada de cada paso
4. **Idempotente**: Puedes ejecutar el script múltiples veces sin problemas
