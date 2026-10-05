resource "aws_apigatewayv2_api" "upload_api" {
  name          = "image-processor-${var.environment}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["content-type"]
    allow_methods = ["POST", "OPTIONS"]
    allow_origins = ["*"]
  }
}

resource "aws_apigatewayv2_integration" "upload_lambda" {
  api_id = aws_apigatewayv2_api.upload_api.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.upload_lambda.arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "upload" {
  api_id = aws_apigatewayv2_api.upload_api.id

  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.upload_lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.upload_api.id

  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway_upload" {
  statement_id  = "AllowAPIGatewayInvokeUpload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.upload_api.execution_arn}/*/*"
}