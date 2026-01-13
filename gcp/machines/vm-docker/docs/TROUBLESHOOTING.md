# Troubleshooting: Actualización Automática de Microservicios

## Problema: Los microservicios no se despliegan después de `terraform apply`

### Síntomas
- Agregas un nuevo microservicio a `terraform.tfvars`
- Ejecutas `terraform apply`
- El metadata de la VM se actualiza
- PERO los nuevos microservicios NO se despliegan
- El timer systemd no detecta cambios

### Diagnóstico

#### 1. Verificar que el metadata se actualizó

Desde la VM:

```bash
# Conectarte a la VM
make ssh

# Ver el metadata actual
curl -s -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/microservices_json \
  | base64 -d | python3 -m json.tool
```

Si el metadata está vacío o no contiene los nuevos microservicios:
- Verifica que `terraform apply` se completó correctamente
- Verifica que hay microservicios definidos en `terraform.tfvars`

#### 2. Verificar que el timer systemd está activo

```bash
# Ver estado del timer
sudo systemctl status watch-metadata.timer

# Verificar que está habilitado
sudo systemctl is-enabled watch-metadata.timer

# Si no está habilitado, habilitarlo
sudo systemctl enable watch-metadata.timer
sudo systemctl start watch-metadata.timer
```

#### 3. Verificar logs del sistema de monitoreo

```bash
# Ver logs del script de monitoreo
tail -f /var/log/watch-metadata.log

# Ver última ejecución del servicio
sudo systemctl status watch-metadata.service

# Ver journal de systemd
sudo journalctl -u watch-metadata.service -f
```

#### 4. Verificar que los scripts existen

```bash
# Verificar que el script de monitoreo existe
ls -la /opt/scripts/watch_metadata.sh

# Verificar que el script de actualización existe
ls -la /opt/scripts/update_microservices.sh

# Verificar permisos
ls -la /opt/scripts/ | grep -E "watch_metadata|update_microservices"
```

Si los scripts NO existen:
- El startup script aún no terminó de ejecutarse
- Espera 2-3 minutos y verifica de nuevo
- Revisa los logs: `tail -f /var/log/startup-script.log`

#### 5. Ejecutar diagnóstico manual

En la VM, ejecuta:

```bash
# Obtener metadata
MICROSERVICES_JSON=$(curl -s -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/microservices_json \
  | base64 -d)

# Ver el JSON
echo "$MICROSERVICES_JSON" | python3 -m json.tool

# Ejecutar script manualmente
bash /opt/scripts/update_microservices.sh "$MICROSERVICES_JSON"
```

O usar el helper script:

```bash
bash /opt/scripts/helper_update_services.sh update-from-metadata
```

### Soluciones

#### Solución 1: Reiniciar el timer systemd

Si el timer no está funcionando correctamente:

```bash
# Reiniciar el timer
sudo systemctl restart watch-metadata.timer

# Verificar estado
sudo systemctl status watch-metadata.timer
```

#### Solución 2: Ejecutar manualmente el script de monitoreo

Para forzar una ejecución inmediata sin esperar al timer:

```bash
# Ejecutar manualmente
bash /opt/scripts/watch_metadata.sh

# O usar el helper script
bash /opt/scripts/helper_update_services.sh update-from-metadata
```

#### Solución 3: Verificar configuración del timer

Si el timer no se está ejecutando:

```bash
# Ver configuración del timer
cat /etc/systemd/system/watch-metadata.timer

# Ver configuración del servicio
cat /etc/systemd/system/watch-metadata.service

# Recargar systemd
sudo systemctl daemon-reload

# Reiniciar timer
sudo systemctl restart watch-metadata.timer
```

#### Solución 4: Recrear el timer (último recurso)

Si el timer está corrupto, puedes recrearlo:

```bash
# Detener y deshabilitar
sudo systemctl stop watch-metadata.timer
sudo systemctl disable watch-metadata.timer

# Eliminar archivos
sudo rm /etc/systemd/system/watch-metadata.{service,timer}

# Recargar systemd
sudo systemctl daemon-reload

# Recrear el timer ejecutando el startup script de nuevo
# O simplemente recrear la VM con terraform
```

---

## Problema: El timer se ejecuta pero los microservicios no se despliegan

### Síntomas
- El timer está activo y ejecutándose
- Los logs muestran que `watch_metadata.sh` se ejecuta
- PERO los microservicios no se despliegan

### Diagnóstico

#### 1. Verificar logs del script de monitoreo

```bash
# Ver logs completos
cat /var/log/watch-metadata.log

# Ver últimas líneas
tail -50 /var/log/watch-metadata.log
```

Busca errores como:
- "No se pudo obtener metadata"
- "Error al ejecutar update_microservices.sh"
- "Permission denied"

#### 2. Verificar que el hash cambió

El script solo ejecuta `update_microservices.sh` si detecta un cambio en el hash:

```bash
# Ver hash actual
cat /tmp/microservices_last_hash.txt 2>/dev/null || echo "No existe"

# Forzar ejecución eliminando el hash
rm -f /tmp/microservices_last_hash.txt
bash /opt/scripts/watch_metadata.sh
```

#### 3. Ejecutar el script de actualización manualmente

```bash
# Obtener metadata
MICROSERVICES_JSON=$(curl -s -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/microservices_json \
  | base64 -d)

# Ejecutar script directamente
bash /opt/scripts/update_microservices.sh "$MICROSERVICES_JSON"
```

Observa los errores que aparecen.

### Soluciones

#### Solución 1: Verificar permisos

```bash
# Verificar permisos de los scripts
ls -la /opt/scripts/update_microservices.sh
ls -la /opt/scripts/watch_metadata.sh

# Deben ser ejecutables (deben tener 'x')
# Si no, hacerlos ejecutables
sudo chmod +x /opt/scripts/update_microservices.sh
sudo chmod +x /opt/scripts/watch_metadata.sh
```

#### Solución 2: Verificar directorio de despliegue

```bash
# Verificar que el directorio existe
ls -la /home/ubuntu/

# Verificar permisos
ls -ld /home/ubuntu/

# Si no existe o no tiene permisos, crear
sudo mkdir -p /home/ubuntu
sudo chown ubuntu:ubuntu /home/ubuntu
```

#### Solución 3: Ejecutar con diagnóstico

Usa el script de diagnóstico:

```bash
bash /opt/scripts/diagnose_update.sh
```

Este script verifica:
- Estado del timer
- Existencia de scripts
- Permisos
- Metadata
- Hash actual

---

## Problema: Los microservicios se despliegan pero no inician

### Síntomas
- Los microservicios se clonan correctamente
- Los archivos `.env` se crean
- PERO los contenedores Docker no se inician
- O se inician pero fallan inmediatamente

### Diagnóstico

#### 1. Verificar logs del despliegue

```bash
# Ver logs del script de actualización
tail -100 /var/log/watch-metadata.log | grep -A 20 "Deploying"

# O ejecutar manualmente con salida detallada
bash /opt/scripts/helper_update_services.sh update-from-metadata
```

#### 2. Verificar estado de Docker

```bash
# Verificar que Docker está corriendo
sudo systemctl status docker

# Verificar permisos
groups
# Debes estar en el grupo 'docker'

# Si no estás en el grupo docker, agregarte
sudo usermod -aG docker $USER
newgrp docker
```

#### 3. Verificar el microservicio específico

```bash
# Ir al directorio del microservicio
cd /home/ubuntu/<nombre-microservicio>

# Ver archivo .env
cat .env

# Ver docker-compose.yml
cat docker-compose.yml

# Intentar iniciar manualmente
docker-compose up -d

# Ver logs
docker-compose logs
```

### Soluciones

#### Solución 1: Verificar archivo .env

El archivo `.env` puede tener problemas:

```bash
# Ver contenido
cat /home/ubuntu/<nombre-microservicio>/.env

# Verificar formato (sin caracteres extraños)
cat -A /home/ubuntu/<nombre-microservicio>/.env
```

#### Solución 2: Verificar docker-compose.yml

```bash
# Validar sintaxis
docker-compose config

# Ver configuración completa
docker-compose config --services
```

#### Solución 3: Ver logs de Docker

```bash
# Ver logs del contenedor
docker logs <container_id>

# Ver logs de docker-compose
docker-compose logs -f
```

---

## Problemas Comunes

### 1. "Timer no está activo"

**Causa**: El timer systemd no está habilitado o iniciado

**Solución**:
```bash
sudo systemctl enable watch-metadata.timer
sudo systemctl start watch-metadata.timer
sudo systemctl status watch-metadata.timer
```

### 2. "Scripts no existen en /opt/scripts/"

**Causa**: El startup script aún no terminó de ejecutarse

**Solución**:
- Espera 2-3 minutos después de crear la VM
- Verifica que el startup script terminó: `tail /var/log/startup-script.log`
- Si hay errores, corrígelos y recrea la VM

### 3. "No se puede obtener metadata (404)"

**Causa**: El metadata no existe en la VM

**Solución**:
- Verifica que ejecutaste `terraform apply` con microservicios definidos
- Verifica que la VM fue creada correctamente
- El metadata se crea automáticamente cuando hay microservicios en `terraform.tfvars`

### 4. "Permiso denegado al ejecutar scripts"

**Causa**: Los scripts no tienen permisos de ejecución

**Solución**:
```bash
sudo chmod +x /opt/scripts/*.sh
sudo chown ubuntu:ubuntu /opt/scripts/*.sh
```

### 5. "El hash no cambia aunque cambie terraform.tfvars"

**Causa**: El hash se calcula basado en el contenido, si el contenido es el mismo, el hash no cambia

**Solución**:
- Verifica que realmente cambiaste algo en la lista de microservicios
- Forza ejecución eliminando el hash: `rm /tmp/microservices_last_hash.txt`
- Ejecuta manualmente: `bash /opt/scripts/watch_metadata.sh`

---

## Verificación Final

Después de `terraform apply`, verifica:

1. **El metadata se actualizó**:
   ```bash
   curl -s -H 'Metadata-Flavor: Google' \
     http://metadata.google.internal/computeMetadata/v1/instance/attributes/microservices_json \
     | base64 -d | python3 -m json.tool
   ```

2. **El timer está activo**:
   ```bash
   sudo systemctl status watch-metadata.timer
   ```

3. **Los microservicios están desplegados**:
   ```bash
   ls -la /home/ubuntu/
   docker ps
   ```

4. **Los logs muestran el despliegue**:
   ```bash
   tail -100 /var/log/watch-metadata.log
   ```

---

## Comandos Útiles de Diagnóstico

```bash
# Diagnóstico completo
bash /opt/scripts/diagnose_update.sh

# Ver estado del sistema
sudo systemctl status watch-metadata.{timer,service}

# Ver logs
tail -f /var/log/watch-metadata.log
sudo journalctl -u watch-metadata.service -f

# Forzar ejecución
bash /opt/scripts/watch_metadata.sh

# Usar helper script
bash /opt/scripts/helper_update_services.sh status
bash /opt/scripts/helper_update_services.sh update-from-metadata
```
