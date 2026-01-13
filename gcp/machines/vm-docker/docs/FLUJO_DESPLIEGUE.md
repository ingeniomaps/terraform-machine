# Flujo Completo de Despliegue y Actualización de Microservicios

## Resumen

Este documento explica cómo funciona el sistema de despliegue y actualización automática de microservicios en la VM. El sistema utiliza metadata de GCP y un servicio systemd que monitorea cambios automáticamente.

## Proceso Completo

### 1. Creación Inicial de la VM

Cuando ejecutas `terraform apply` por primera vez:

#### Paso 1.1: Terraform procesa la configuración

```bash
cd machines/vm-docker
terraform apply
```

- Terraform lee `terraform.tfvars` y procesa la lista de microservicios
- Si `env_file` es una ruta (ej: `"envs/gateway.env"`), lee el contenido del archivo
- Si `env_file` es contenido directo, lo usa tal cual
- Genera un JSON con todos los microservicios procesados

#### Paso 1.2: Terraform crea la VM

- Crea el recurso `google_compute_instance` a través del módulo `vm-base`
- El `startup_script` incluye:
  1. **Instalación de Docker** (`docker_install.sh`)
  2. **Instalación de Certbot** (opcional)
  3. **Copia de scripts de gestión** a `/opt/scripts/`:
     - `update_microservices.sh` - Script para actualizar microservicios
     - `watch_metadata.sh` - Script para monitorear cambios en metadata
     - `helper_update_services.sh` - Script helper para gestión manual
     - `diagnose_update.sh` - Script de diagnóstico
  4. **Configuración de systemd timer** para monitorear cambios
  5. **Despliegue inicial de microservicios** (`microservices_deploy.sh`)

#### Paso 1.3: Metadata de la VM

- Terraform guarda el JSON de microservicios en el metadata de la VM:
  ```hcl
  metadata = {
    microservices_json = base64encode(json_de_microservicios)
  }
  ```

#### Paso 1.4: La VM inicia y ejecuta el startup script

Cuando la VM arranca, ejecuta automáticamente:

1. **Instala Docker y Docker Compose**

   - Actualiza el sistema
   - Instala Docker desde el repositorio oficial
   - Agrega todos los usuarios al grupo docker
   - Inicia el servicio Docker

2. **Copia los scripts de gestión**

   ```bash
   mkdir -p /opt/scripts
   # Scripts copiados desde modules/vm-docker/scripts/
   ```

3. **Configura systemd timer para monitoreo**

   - Crea servicio: `/etc/systemd/system/watch-metadata.service`
   - Crea timer: `/etc/systemd/system/watch-metadata.timer`
   - Habilita y inicia el timer (ejecuta cada minuto)

4. **Despliega microservicios iniciales** (`microservices_deploy.sh`)
   - Para cada microservicio en la lista:
     - Verifica si ya existe en `/home/ubuntu/{nombre}`
     - Si NO existe:
       - Clona el repositorio desde `repo_url` en la rama `branch`
       - Crea el archivo `.env` con el contenido de `env_file`
       - Ejecuta `launch_command` (si está definido) o `docker-compose up -d`
     - Si ya existe, lo omite

---

### 2. Actualización de la Lista de Microservicios

Cuando agregas un nuevo microservicio a `terraform.tfvars`:

#### Paso 2.1: Modificas `terraform.tfvars`

```hcl
microservices = [
  {
    name           = "gateway"
    repo_url       = "https://..."
    branch         = "staging"
    env_file       = "envs/gateway.env"
    launch_command = null
  },
  # NUEVO MICROSERVICIO
  {
    name           = "api-service"
    repo_url       = "https://..."
    branch         = "main"
    env_file       = "envs/api.env"
    launch_command = "docker-compose up -d"
  }
]
```

#### Paso 2.2: Ejecutas `terraform apply`

- **Terraform detecta cambios** en la lista de microservicios
- **Actualiza el metadata de la VM** con el nuevo JSON de microservicios
- El metadata se actualiza automáticamente a través del módulo `vm-base`

#### Paso 2.3: Detección automática en la VM

El timer systemd (`watch-metadata.timer`) ejecuta `watch_metadata.sh` cada minuto:

1. **El script obtiene el metadata actual** desde el metadata server de GCP
2. **Calcula un hash** del contenido
3. **Compara con el hash anterior** (guardado en `/tmp/microservices_last_hash.txt`)
4. **Si detecta un cambio**:
   - Decodifica el JSON desde base64
   - Ejecuta `/opt/scripts/update_microservices.sh` con el JSON
   - Actualiza el hash guardado

#### Paso 2.4: El script procesa los microservicios

El script `update_microservices.sh`:

1. Recibe el JSON completo de microservicios
2. Procesa cada microservicio
3. Para cada uno, llama a `deploy_service()`:
   - **Verifica si existe** en `/home/ubuntu/{nombre}`
   - Si existe: lo omite
   - Si NO existe:
     - Clona el repositorio
     - Crea el archivo `.env`
     - Ejecuta `launch_command` (si está definido) o `docker-compose up -d`

**Resultado**: Solo el nuevo microservicio se despliega, los existentes se omiten.

---

### 3. Actualización de un Microservicio Existente

**IMPORTANTE**: El sistema actual NO actualiza automáticamente microservicios existentes. Solo despliega los nuevos.

Si quieres actualizar un microservicio existente, tienes estas opciones:

#### Opción A: Actualización Manual (recomendado para cambios de código)

```bash
# Conectarte a la VM usando Makefile
make ssh

# Ir al directorio del microservicio
cd /home/ubuntu/gateway

# Actualizar código desde el repositorio
git pull origin staging

# Reconstruir y reiniciar
docker-compose down
docker-compose up -d --build
```

#### Opción B: Usar Makefile (recomendado)

```bash
# Actualizar todos los microservicios
make update-all

# O actualizar uno específico desde la VM
make ssh
bash /opt/scripts/helper_update_services.sh update-one gateway
```

#### Opción C: Forzar re-despliegue (eliminar y dejar que se recree)

```bash
# Conectarte a la VM
make ssh

# Eliminar el microservicio
rm -rf /home/ubuntu/gateway

# Ejecutar manualmente el script de actualización
bash /opt/scripts/helper_update_services.sh update-from-metadata
```

---

## Resumen del Flujo

### Primera vez (creación de VM):

```
terraform apply
  → Crea VM con startup script
  → VM inicia y ejecuta startup script
  → Instala Docker
  → Copia scripts de gestión
  → Configura systemd timer
  → Despliega TODOS los microservicios de terraform.tfvars
```

### Agregar nuevo microservicio:

```
Modificar terraform.tfvars (agregar microservicio)
  → terraform apply
  → Actualiza metadata de la VM
  → Timer systemd detecta cambio (máximo 1 minuto)
  → Ejecuta update_microservices.sh
  → Script despliega SOLO el nuevo microservicio
```

### Actualizar microservicio existente:

```
NO automático actualmente
Opción: Actualización manual vía SSH
Opción: Usar helper_update_services.sh
Opción: Eliminar y dejar que se recree
```

---

## Actualización Manual desde dentro de la VM

Si necesitas actualizar microservicios manualmente desde dentro de la VM:

### Método 1: Usar Makefile (recomendado)

```bash
# Actualizar todos los microservicios
make update-all

# Desplegar microservicios nuevos
make deploy
```

### Método 2: Usar el script helper desde la VM

El script helper está disponible en `/opt/scripts/helper_update_services.sh`:

```bash
# Conectarse a la VM
make ssh

# Ver ayuda
bash /opt/scripts/helper_update_services.sh help

# Actualizar desde metadata (despliega solo nuevos)
bash /opt/scripts/helper_update_services.sh update-from-metadata

# Actualizar un microservicio específico (git pull + rebuild)
bash /opt/scripts/helper_update_services.sh update-one gateway

# Actualizar TODOS los microservicios (git pull + rebuild)
bash /opt/scripts/helper_update_services.sh update-all

# Re-desplegar un microservicio desde cero
bash /opt/scripts/helper_update_services.sh redeploy api-service

# Ver estado de todos los microservicios
bash /opt/scripts/helper_update_services.sh status

# Listar todos los microservicios desplegados
bash /opt/scripts/helper_update_services.sh list

# Ver logs de un microservicio específico
bash /opt/scripts/helper_update_services.sh logs gateway
```

### Método 3: Actualizar manualmente un microservicio

```bash
# Conectarte a la VM
make ssh

# Ir al directorio del microservicio
cd /home/ubuntu/<nombre-microservicio>

# Ver el branch actual
git branch

# Actualizar código desde el repositorio
git pull origin <branch>

# Detener contenedores actuales
docker-compose down

# Reconstruir y reiniciar
docker-compose up -d --build

# Ver logs para verificar que funciona
docker-compose logs -f
```

---

## Verificación y Utilidades

### Ver qué microservicios están desplegados:

```bash
# Conectarte a la VM
make ssh

# Ver directorios de microservicios
ls -la /home/ubuntu/

# Ver contenedores Docker corriendo
docker ps

# Ver todos los contenedores (incluyendo detenidos)
docker ps -a

# Ver logs del startup script (desde local)
make logs
```

### Ver metadata actual de microservicios:

```bash
# Desde la VM
curl -s -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/microservices_json \
  | base64 -d | python3 -m json.tool
```

### Ver estado del sistema de monitoreo:

```bash
# Ver estado del timer
sudo systemctl status watch-metadata.timer

# Ver logs del script de monitoreo
tail -f /var/log/watch-metadata.log

# Ver última ejecución del servicio
sudo systemctl status watch-metadata.service
```

### Verificar que el script de actualización está disponible:

```bash
# Verificar que existe
ls -la /opt/scripts/update_microservices.sh

# Ver contenido (primera parte)
head -20 /opt/scripts/update_microservices.sh

# Probar que es ejecutable
bash -n /opt/scripts/update_microservices.sh  # Valida sintaxis sin ejecutar
```

---

## Notas Importantes

1. **Metadata vs Realidad**: El metadata de la VM puede tener una lista diferente a lo que realmente está desplegado. El metadata refleja lo que está en `terraform.tfvars`.

2. **Cambios en .env**: Si cambias el archivo `.env` en `terraform.tfvars`, el microservicio NO se actualiza automáticamente. Debes re-desplegarlo usando el helper script.

3. **Cambios en el branch**: Si cambias el branch en `terraform.tfvars`, el microservicio NO se actualiza automáticamente. Debes actualizarlo manualmente o re-desplegarlo.

4. **Tiempo de detección**: El timer ejecuta el script cada minuto, por lo que los cambios se detectan en máximo 1-2 minutos después de `terraform apply`.

5. **Script Helper**: El script helper (`/opt/scripts/helper_update_services.sh`) está disponible automáticamente en todas las VMs después del startup. Es la forma más fácil de gestionar actualizaciones manuales.

6. **Sin IP pública**: El sistema funciona sin IP pública porque usa el metadata server de GCP, que es accesible desde dentro de la VM.
