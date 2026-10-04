# Obtener información de la cuenta actual de AWS de forma dinámica
data "aws_caller_identity" "current" {}

# 1. Bucket S3 privado para las imágenes con force_destroy = true
resource "aws_s3_bucket" "images_bucket" {
  bucket        = "image-processor-${var.environment}-images-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

# 2. Carpetas virtuales (prefijos) dentro del Bucket
resource "aws_s3_object" "uploads_folder" {
  bucket = aws_s3_bucket.images_bucket.id
  key    = "uploads/"
}

resource "aws_s3_object" "processed_folder" {
  bucket = aws_s3_bucket.images_bucket.id
  key    = "processed/"
}

# 3a. Dead-Letter Queue (DLQ) para recibir mensajes tras 3 intentos fallidos (retención 14 días)
resource "aws_sqs_queue" "image_dlq" {
  name                      = "image-processor-${var.environment}-dlq"
  message_retention_seconds = 1209600 # 14 días
}

# 3b. Cola SQS principal (visibility_timeout = 360, receive_wait_time = 20)
resource "aws_sqs_queue" "image_queue" {
  name                       = "image-processor-${var.environment}-queue"
  visibility_timeout_seconds = 360
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_dlq.arn
    maxReceiveCount     = 3
  })
}

# 4a. Política de SQS para permitir eventos desde S3
resource "aws_sqs_queue_policy" "queue_policy" {
  queue_url = aws_sqs_queue.image_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.image_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.images_bucket.arn
          }
        }
      }
    ]
  })
}

# 4b. Notificación S3 para enviar evento a SQS al subir archivos a uploads/
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.images_bucket.id

  queue {
    queue_arn     = aws_sqs_queue.image_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
  }

  depends_on = [aws_sqs_queue_policy.queue_policy]
}
