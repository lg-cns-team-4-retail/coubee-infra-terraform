# SNS Topic for DLQ Alerts
resource "aws_sns_topic" "dlq_alerts" {
  name = "${var.project_name}-notification-dlq-alerts"
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "dispatcher_logs" {
  name              = "/aws/lambda/${var.project_name}-notification-dispatcher"
  retention_in_days = 14

  tags = {
    Name = "dispatcher-log"
  }
}

resource "aws_cloudwatch_log_group" "worker_logs" {
  name              = "/aws/lambda/${var.project_name}-notification-worker"
  retention_in_days = 14

  tags = {
    Name = "worker-log"
  }
}

resource "aws_cloudwatch_log_group" "s3_log_group" {
  name              = "/aws/lambda/s3_import"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "dataset_log_group" {
  name              = "/personalize/dataset_import"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "solution_log_group" {
  name              = "/aws/lambda/solution_import"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "batch_inference_import_log_group" {
  name              = "/aws/lambda/batch_inference_import"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "load_server_clean_log_group" {
  name              = "/aws/lambda/load_server_cleant"
  retention_in_days = 14
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "notification_dashboard" {
  dashboard_name = "${var.project_name}-notification-system"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["NotificationSystem/Dispatcher", "DispatcherSuccess"],
            [".", "DispatcherError"],
            ["NotificationSystem", "ImmediateSend"],
            [".", "QueuedNotifications"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "ap-northeast-2"
          title   = "Notification System Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/aws/lambda/${var.project_name}-notification-dispatcher' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = "ap-northeast-2"
          title   = "Dispatcher Logs"
        }
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "dispatcher_errors" {
  alarm_name          = "${var.project_name}-notification-dispatcher-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors dispatcher lambda errors"
  alarm_actions       = [aws_sns_topic.dlq_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.dispatcher.function_name
  }

  tags = {
    Name = "dispatcher_errors"
  }
}

resource "aws_cloudwatch_metric_alarm" "worker_errors" {
  alarm_name          = "${var.project_name}-notification-worker-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors worker lambda errors"
  alarm_actions       = [aws_sns_topic.dlq_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.worker.function_name
  }

  tags = {
    Name = "worker_errors"
  }
}

# Step Function 실행 로그를 저장할 CloudWatch Log Group
resource "aws_cloudwatch_log_group" "sfn_log_group" {
  name              = "/aws/vendedlogs/states/PersonalizePipelineLogs"
  retention_in_days = 14 # 로그 보존 기간 (일)
}