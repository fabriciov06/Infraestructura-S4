# Rol IAM para la Lambda de Upload
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

# Política básica de ejecución para CloudWatch Logs
resource "aws_iam_role_policy_attachment" "upload_lambda_logs" {
  role       = aws_iam_role.upload_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Política adicional para permitir acceso de escritura en la ruta uploads/ del S3 y SQS
resource "aws_iam_policy" "upload_lambda_storage_policy" {
  name = "image-processor-${var.environment}-upload-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "upload_lambda_storage_attach" {
  role       = aws_iam_role.upload_lambda_role.name
  policy_arn = aws_iam_policy.upload_lambda_storage_policy.arn
}

# Recurso de la Función Lambda para Node.js 20.x
resource "aws_lambda_function" "upload_lambda" {
  filename      = "src/upload-lambda/index.js"
  function_name = "image-processor-${var.environment}-upload"
  role          = aws_iam_role.upload_lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }
}