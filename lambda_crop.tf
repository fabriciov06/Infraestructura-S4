# ============================================================
# VARIABLES DE INTEGRACION
# ============================================================
# Estos valores serán conectados posteriormente con
# el bucket S3 y la cola SQS creados por otros integrantes.

variable "crop_bucket_name" {
  description = "Nombre del bucket S3 que contiene uploads/ y processed/"
  type        = string
}

variable "crop_main_queue_arn" {
  description = "ARN de la cola SQS principal que dispara Lambda Crop"
  type        = string
}

# ============================================================
# IAM - POLITICA DE CONFIANZA
# ============================================================
# Permite que el servicio AWS Lambda utilice este rol.

data "aws_iam_policy_document" "crop_lambda_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole"
    ]

    principals {
      type = "Service"

      identifiers = [
        "lambda.amazonaws.com"
      ]
    }
  }
}


# ============================================================
# IAM ROLE DE LAMBDA CROP
# ============================================================

resource "aws_iam_role" "crop_lambda_role" {
  name = "image-processor-${var.environment}-lambda-crop-role"

  assume_role_policy = data.aws_iam_policy_document.crop_lambda_assume_role.json
}


# ============================================================
# PERMISOS PARA CLOUDWATCH LOGS
# ============================================================

resource "aws_iam_role_policy_attachment" "crop_lambda_logs" {
  role = aws_iam_role.crop_lambda_role.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# ============================================================
# PERMISOS S3 Y SQS
# ============================================================

data "aws_iam_policy_document" "crop_lambda_permissions" {

  # Leer solamente las imagenes de uploads/
  statement {
    sid    = "ReadUploads"
    effect = "Allow"

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "arn:aws:s3:::${var.crop_bucket_name}/uploads/*"
    ]
  }


  # Escribir solamente en processed/
  statement {
    sid    = "WriteProcessed"
    effect = "Allow"

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "arn:aws:s3:::${var.crop_bucket_name}/processed/*"
    ]
  }


  # Consumir mensajes de la cola SQS principal
  statement {
    sid    = "ConsumeMainQueue"
    effect = "Allow"

    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]

    resources = [
      var.crop_main_queue_arn
    ]
  }
}


# ============================================================
# ASIGNAR LA POLITICA AL ROL
# ============================================================

resource "aws_iam_role_policy" "crop_lambda_policy" {
  name = "image-processor-${var.environment}-lambda-crop-policy"

  role = aws_iam_role.crop_lambda_role.id

  policy = data.aws_iam_policy_document.crop_lambda_permissions.json
}


# ============================================================
# EMPAQUETAR EL CODIGO DE LA LAMBDA
# ============================================================

data "archive_file" "crop_lambda_package" {
  type = "zip"

  source_dir = "${path.module}/src/crop-lambda"

  output_path = "${path.module}/crop-lambda.zip"
}


# ============================================================
# AWS LAMBDA CROP
# ============================================================

resource "aws_lambda_function" "crop_lambda" {
  function_name = "image-processor-${var.environment}-lambda-crop"

  description = "Procesa imagenes de uploads y genera PNG circular de 40x40"

  filename = data.archive_file.crop_lambda_package.output_path

  source_code_hash = data.archive_file.crop_lambda_package.output_base64sha256

  role = aws_iam_role.crop_lambda_role.arn

  handler = "index.handler"

  # Requisito indicado por el profesor
  runtime = "nodejs20.x"

  # Requisitos indicados en la tarea
  memory_size = 512
  timeout     = 60

  # Sharp fue instalado para x86_64
  architectures = [
    "x86_64"
  ]

  environment {
    variables = {
      IMAGE_BUCKET_NAME = var.crop_bucket_name
      UPLOAD_PREFIX     = "uploads/"
      PROCESSED_PREFIX  = "processed/"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.crop_lambda_logs,
    aws_iam_role_policy.crop_lambda_policy
  ]
}


# ============================================================
# SQS -> LAMBDA
# ============================================================

resource "aws_lambda_event_source_mapping" "crop_lambda_sqs" {
  event_source_arn = var.crop_main_queue_arn

  function_name = aws_lambda_function.crop_lambda.arn

  # Procesamiento por lotes
  batch_size = 5

  # Permite informar solo los mensajes que fallen
  function_response_types = [
    "ReportBatchItemFailures"
  ]

  enabled = true

  depends_on = [
    aws_iam_role_policy.crop_lambda_policy
  ]
}