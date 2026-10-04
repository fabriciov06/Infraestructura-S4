data "archive_file" "upload_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src/upload-lambda"
  output_path = "${path.module}/files/upload_lambda.zip"
}

resource "aws_iam_role" "upload_lambda_role" {
  name = "image-processor-${var.environment}-upload-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "upload_lambda_logs" {
  role       = aws_iam_role.upload_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "upload_lambda_s3_policy" {
  name = "image-processor-${var.environment}-upload-s3-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::image-processor-${var.environment}-*/*/uploads/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "upload_lambda_s3_attach" {
  role       = aws_iam_role.upload_lambda_role.name
  policy_arn = aws_iam_policy.upload_lambda_s3_policy.arn
}

resource "aws_lambda_function" "upload_lambda" {
  filename         = data.archive_file.upload_lambda_zip.output_path
  source_code_hash = data.archive_file.upload_lambda_zip.output_base64sha256
  function_name    = "image-processor-${var.environment}-upload"
  role             = aws_iam_role.upload_lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  memory_size      = 256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      BUCKET_NAME = "image-processor-${var.environment}-bucket"
    }
  }
}