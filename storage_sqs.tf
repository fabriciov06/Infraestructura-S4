data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "images_bucket" {
  bucket        = "image-processor-${var.environment}-images-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_object" "uploads_folder" {
  bucket = aws_s3_bucket.images_bucket.id
  key    = "uploads/"
}

resource "aws_s3_object" "processed_folder" {
  bucket = aws_s3_bucket.images_bucket.id
  key    = "processed/"
}

resource "aws_sqs_queue" "image_dlq" {
  name                      = "image-processor-${var.environment}-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "image_queue" {
  name                       = "image-processor-${var.environment}-queue"
  visibility_timeout_seconds = 360
  receive_wait_time_seconds  = 20
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_policy" "queue_policy" {
  queue_url = aws_sqs_queue.image_queue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.image_queue.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_s3_bucket.images_bucket.arn
        }
      }
    }]
  })
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.images_bucket.id

  queue {
    queue_arn     = aws_sqs_queue.image_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
  }
}
