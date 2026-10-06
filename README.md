# AWS + Lambda Integration (Terraform)

Infraestructura como Código (IaC) para procesar imágenes utilizando AWS S3, Lambda, SQS y API Gateway. Este proyecto está parametrizado para soportar múltiples entornos aislados (dev, qa, prod).

## Requisitos Previos
* Terraform instalado (versión >= 1.5.0).
* AWS CLI configurado con credenciales activas.
* Perfil local de AWS CLI configurado bajo el nombre `wlupao` (vía IAM Identity Center/SSO).

## Instrucciones de Ejecución

### 1. Inicializar los módulos y providers:
```bash
terraform init
```

### 2. Validar la sintaxis del código:
```bash
terraform validate
```

### 3. Desplegar la infraestructura:
Para levantar la arquitectura, debes especificar el archivo de variables del entorno correspondiente (`dev`, `qa`, o `prod`):
```bash
terraform apply -var-file="envs/dev.tfvars"
```

### 4. Destruir los recursos:
Para limpiar la cuenta de AWS y evitar costos, utiliza el comando de destrucción indicando el entorno activo:
```bash
terraform destroy -var-file="envs/dev.tfvars"
```
