# EventBridge Custom Event Bus
resource "aws_cloudwatch_event_bus" "notification_bus" {
  name = "notification_bus"
}

# EventBridge Rule
resource "aws_cloudwatch_event_rule" "order_status_rule" {
  name           = "notification_send_rule"
  event_bus_name = aws_cloudwatch_event_bus.notification_bus.name

  event_pattern = jsonencode({
    "source"      = ["coubee.notification"]
    "detail-type" = ["notification_send"]
  })
}

# EventBridge Target: Dispatcher Lambda
resource "aws_cloudwatch_event_target" "dispatcher_target" {
  rule           = aws_cloudwatch_event_rule.order_status_rule.name
  event_bus_name = aws_cloudwatch_event_bus.notification_bus.name
  target_id      = "DispatcherLambda"
  arn            = aws_lambda_function.dispatcher.arn
}

resource "aws_sfn_state_machine" "personalize_pipeline" {
  name     = "PersonalizePipelineStateMachine" # 상태 머신의 이름
  role_arn = aws_iam_role.step_function_exec.arn
  # file() 함수를 사용해 외부 JSON 파일의 내용을 읽어와서 정의로 사용합니다.
  definition = file("${path.module}/personalize_pipeline.json")
  # 로깅 설정 (선택 사항이지만 디버깅에 매우 유용하므로 강력히 권장합니다.)
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_log_group.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
}