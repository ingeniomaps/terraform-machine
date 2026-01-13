# ============================================================================
# MAKEFILE PARA VM-DOCKER
# ============================================================================

# Silenciar mensajes de entrada/salida de directorios
MAKEFLAGS += --no-print-directory

.PHONY: help init plan apply destroy outputs outputs-json fmt validate clean \
	ssh deploy update-services restore-ssh diagnose-iap up down status \
	copy-deployment-scripts ssh-cmd update-all ssh-exec logs \
	microservices-status microservices-list microservices-logs reload

# Colores para output
GREEN  := \033[0;32m
YELLOW := \033[1;33m
RED    := \033[0;31m
BLUE   := \033[0;34m
NC     := \033[0m # No Color

# Variables
SSH_USER := ubuntu
SCRIPTS_DIR := scripts/helpers

help: ## Mostrar esta ayuda
	@echo "$(GREEN)Comandos disponibles:$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; \
		{printf "  $(YELLOW)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BLUE)Variables importantes (si terraform está aplicado):$(NC)"
	@INSTANCE_NAME=$$(terraform output -raw instance_name 2>/dev/null 2>&1 | \
		grep -vE "(No outputs found|Warning:|Error:)" | head -1 || echo ""); \
	INSTANCE_ZONE=$$(terraform output -raw instance_zone 2>/dev/null 2>&1 | \
		grep -vE "(No outputs found|Warning:|Error:)" | head -1 || echo ""); \
	PROJECT_ID=$$(terraform output -raw project_id 2>/dev/null 2>&1 | \
		grep -vE "(No outputs found|Warning:|Error:)" | head -1 || \
		grep '^project_id' terraform.tfvars 2>/dev/null | \
		sed 's/.*"\(.*\)".*/\1/' | head -1 || echo ""); \
	if [ -z "$$INSTANCE_NAME" ] && [ -z "$$INSTANCE_ZONE" ]; then \
		echo "  $(YELLOW)Ejecuta 'terraform apply' primero$(NC)"; \
	else \
		echo "  INSTANCE_NAME: $$INSTANCE_NAME"; \
		echo "  INSTANCE_ZONE: $$INSTANCE_ZONE"; \
		echo "  PROJECT_ID: $$PROJECT_ID"; \
	fi

# ============================================================================
# TERRAFORM BÁSICO
# ============================================================================

init: ## Inicializar Terraform
	@echo "$(GREEN)Inicializando Terraform...$(NC)"
	terraform init

plan: ## Ejecutar terraform plan
	@echo "$(GREEN)Ejecutando terraform plan...$(NC)"
	terraform plan

validate: ## Validar configuración de Terraform
	@echo "$(GREEN)Validando configuración...$(NC)"
	terraform validate

fmt: ## Formatear archivos de Terraform
	@echo "$(GREEN)Formateando archivos...$(NC)"
	terraform fmt -recursive

clean: ## Limpiar archivos temporales de Terraform
	@echo "$(YELLOW)Limpiando archivos temporales...$(NC)"
	rm -f .terraform.lock.hcl
	rm -rf .terraform/
	rm -f terraform.tfstate.backup
	rm -f *.tfplan
	rm -f plan.json
	@echo "$(GREEN)Archivos temporales eliminados$(NC)"

# ============================================================================
# DESPLIEGUE
# ============================================================================

up: plan apply post-deploy ## Alzar la máquina: plan + apply + post-deploy

apply: ## Ejecutar terraform apply
	@echo "$(GREEN)Ejecutando terraform apply...$(NC)"
	terraform apply -auto-approve

destroy: ## Destruir la infraestructura
	@echo "$(RED)ADVERTENCIA: Esto destruirá toda la infraestructura$(NC)"
	@read -p "¿Estás seguro? (yes/no): " confirm && \
		[ "$$confirm" = "yes" ] || exit 1
	terraform destroy

post-deploy: ## Ejecutar comandos post-deploy
	@$(SCRIPTS_DIR)/post_deploy.sh

copy-deployment-scripts: ## Copiar scripts de despliegue personalizados a la VM
	@$(SCRIPTS_DIR)/copy_deployment_scripts.sh

# ============================================================================
# SSH CON PRIORIDAD: .pem > .json > IAP > OS Login > IP pública
# ============================================================================

ssh: ## Conectarse por SSH (prioridad: .pem > .json > IAP > OS Login > IP pública)
	@SSH_USER=$(SSH_USER) $(SCRIPTS_DIR)/ssh_connect.sh

ssh-cmd: ## Mostrar comando SSH (sin ejecutar)
	@SSH_USER=$(SSH_USER) $(SCRIPTS_DIR)/ssh_cmd.sh

# ============================================================================
# GESTIÓN DE MICROSERVICIOS
# ============================================================================

deploy: ## Desplegar microservicios nuevos en la VM
	@SSH_USER=$(SSH_USER) $(SCRIPTS_DIR)/deploy_services.sh

update-services: deploy ## Alias para deploy (actualizar microservicios nuevos)

update-all: ## Actualizar todos los microservicios (git pull + rebuild)
	@SSH_USER=$(SSH_USER) $(SCRIPTS_DIR)/update_all_services.sh

ssh-exec: ## Ejecutar comando en la VM (uso: make ssh-exec CMD="comando")
	@if [ -z "$(CMD)" ]; then \
		echo "$(RED)Error: Debes especificar CMD=comando$(NC)"; \
		exit 1; \
	fi; \
	SSH_USER=$(SSH_USER) $(SCRIPTS_DIR)/ssh_exec.sh "$(CMD)"

# ============================================================================
# GESTIÓN DE CLAVES SSH
# ============================================================================

restore-ssh: ## Restaurar clave SSH perdida
	@echo "$(GREEN)Restaurando clave SSH...$(NC)"
	@./scripts/restore-ssh-key.sh

# ============================================================================
# DIAGNÓSTICO
# ============================================================================

diagnose-iap: ## Diagnosticar problemas de IAP/SSH
	@echo "$(GREEN)Diagnosticando IAP/SSH...$(NC)"
	@./scripts/diagnose-iap.sh

status: ## Mostrar estado de la VM y microservicios
	@$(SCRIPTS_DIR)/vm_status.sh

# ============================================================================
# OUTPUTS
# ============================================================================

outputs: ## Mostrar todos los outputs de Terraform
	@terraform output

outputs-json: ## Mostrar outputs en formato JSON
	@terraform output -json

# ============================================================================
# UTILIDADES
# ============================================================================

logs: ## Ver logs del startup script en la VM (uso: make logs LINES=200 o make logs FOLLOW=true)
	@SSH_USER=$(SSH_USER) FOLLOW=$(FOLLOW) LINES=$(LINES) $(SCRIPTS_DIR)/vm_logs.sh

logs-follow: ## Seguir logs del startup script en tiempo real
	@SSH_USER=$(SSH_USER) FOLLOW=true $(SCRIPTS_DIR)/vm_logs.sh

microservices-status: ## Ver estado de microservicios en la VM
	@$(MAKE) ssh-exec CMD="bash /opt/scripts/helper_update_services.sh status"

microservices-list: ## Listar microservicios desplegados en la VM
	@$(MAKE) ssh-exec CMD="bash /opt/scripts/helper_update_services.sh list"

microservices-logs: ## Ver logs de un microservicio (uso: make microservices-logs SERVICE=gateway)
	@if [ -z "$(SERVICE)" ]; then \
		echo "$(RED)Error: Debes especificar SERVICE=nombre$(NC)"; \
		exit 1; \
	fi; \
	$(MAKE) ssh-exec CMD="bash /opt/scripts/helper_update_services.sh logs $(SERVICE)"

reload: ## Recargar configuración (terraform init + plan)
	@$(MAKE) init
	@$(MAKE) plan
