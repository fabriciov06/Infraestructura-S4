
# IAM - POLITICA DE CONFIANZA


data "aws_iam_policy_document" "crop_lambda_assume_role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}


# IAM ROLE DE LAMBDA CROP


resource "aws_iam_role" "crop_lambda_role" {
  name = "image-processor-${var.environment}-lambda-crop-role"
  assume_role_policy = data.aws_iam_policy_document.crop_lambda_assume_role.json
}


# PERMISOS PARA CLOUDWATCH LOGS


resource "aws_iam_role_policy_attachment" "crop_lambda_logs" {
  role       = aws_iam_role.crop_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# PERMISOS S3 Y SQS


data "aws_iam_policy_document" "crop_lambda_permissions" {
  # Leer solamente las imagenes de uploads/
  statement {
    sid       = "ReadUploads"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.images_bucket.arn}/uploads/*"]
  }

  # Escribir solamente en processed/
  statement {
    sid       = "WriteProcessed"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.images_bucket.arn}/processed/*"]
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
    resources = [aws_sqs_queue.image_queue.arn]
  }
}


# ASIGNAR LA POLITICA AL ROL


resource "aws_iam_role_policy" "crop_lambda_policy" {
  name   = "image-processor-${var.environment}-lambda-crop-policy"
  role   = aws_iam_role.crop_lambda_role.id
  policy = data.aws_iam_policy_document.crop_lambda_permissions.json
}


# EMPAQUETAR EL CODIGO DE LA LAMBDA


data "archive_file" "crop_lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/src/crop-lambda"
  output_path = "${path.module}/crop-lambda.zip"
}


# AWS LAMBDA CROP


resource "aws_lambda_function" "crop_lambda" {
  function_name    = "image-processor-${var.environment}-lambda-crop"
  description      = "Procesa imagenes de uploads y genera PNG circular de 40x40"
  filename         = data.archive_file.crop_lambda_package.output_path
  source_code_hash = data.archive_file.crop_lambda_package.output_base64sha256
  role             = aws_iam_role.crop_lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  memory_size      = 512
  timeout          = 60
  architectures    = ["x86_64"]

  environment {
    variables = {
      IMAGE_BUCKET_NAME = aws_s3_bucket.images_bucket.id
      UPLOAD_PREFIX     = "uploads/"
      PROCESSED_PREFIX  = "processed/"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.crop_lambda_logs,
    aws_iam_role_policy.crop_lambda_policy
  ]
}


# SQS -> LAMBDA


resource "aws_lambda_event_source_mapping" "crop_lambda_sqs" {
  event_source_arn        = aws_sqs_queue.image_queue.arn
  function_name           = aws_lambda_function.crop_lambda.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]
  enabled                 = true

  depends_on = [
    aws_iam_role_policy.crop_lambda_policy
  ]
}