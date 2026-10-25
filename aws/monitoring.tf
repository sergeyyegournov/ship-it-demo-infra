# Monitoring: alarms -> SNS -> email, a dashboard, and a metric filter over the API's JSON request logs.
# Detection that feeds the SDLC loop (bands.yaml) is separate: monitor.yml reads these same metrics.

variable "alarm_email" {
  type        = string
  description = "Address that receives alarm notifications (passed as TF_VAR_alarm_email from a secret; kept out of the public repo)"
}

resource "aws_sns_topic" "alarms" {
  name = "${var.name}-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email # AWS sends a confirmation link; alarms are not delivered until it is clicked
}

locals {
  alb_dims = {
    LoadBalancer = aws_lb.api.arn_suffix
    TargetGroup  = aws_lb_target_group.api.arn_suffix
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
}

# 5xx rate as a percentage of requests. Below 10 requests a minute the ratio is noise, so it reads as 0.
resource "aws_cloudwatch_metric_alarm" "api_5xx_rate" {
  alarm_name          = "${var.name}-api-5xx-rate"
  alarm_description   = "More than 5% of API requests returned 5xx (2 of the last 3 minutes)"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  metric_query {
    id          = "rate"
    expression  = "IF(requests >= 10, 100 * errors / requests, 0)"
    label       = "5xx %"
    return_data = true
  }
  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = local.alb_dims
      period      = 60
      stat        = "Sum"
    }
  }
  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = local.alb_dims
      period      = 60
      stat        = "Sum"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "api_latency_p95" {
  alarm_name          = "${var.name}-api-latency-p95"
  alarm_description   = "API p95 response time above 1s (3 of the last 5 minutes)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.alb_dims
  extended_statistic  = "p95"
  period              = 60
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# No healthy target at all: the site is down. Missing data counts as breaching, because a service
# with no registered task reports nothing.
resource "aws_cloudwatch_metric_alarm" "no_healthy_hosts" {
  alarm_name          = "${var.name}-no-healthy-hosts"
  alarm_description   = "The ALB has no healthy API task"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = local.alb_dims
  statistic           = "Minimum"
  period              = 60
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# What a viewer sees at the edge (CloudFront metrics are global and live in us-east-1).
resource "aws_cloudwatch_metric_alarm" "edge_5xx_rate" {
  alarm_name          = "${var.name}-edge-5xx-rate"
  alarm_description   = "CloudFront 5xx error rate above 5% (2 of the last 3 five-minute periods)"
  namespace           = "AWS/CloudFront"
  metric_name         = "5xxErrorRate"
  dimensions          = { DistributionId = aws_cloudfront_distribution.web.id, Region = "Global" }
  statistic           = "Average"
  period              = 300
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- request logs -> metrics ------------------------------------------------------
# The API logs one JSON line per request: {"msg":"request","method","route","status","ms","version"}.
resource "aws_cloudwatch_log_metric_filter" "server_errors" {
  name           = "${var.name}-5xx"
  log_group_name = aws_cloudwatch_log_group.api.name
  pattern        = "{ $.msg = \"request\" && $.status >= 500 }"

  metric_transformation {
    name          = "Api5xx"
    namespace     = "StatusBoard"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "requests" {
  name           = "${var.name}-requests"
  log_group_name = aws_cloudwatch_log_group.api.name
  pattern        = "{ $.msg = \"request\" }"

  metric_transformation {
    name          = "ApiRequests"
    namespace     = "StatusBoard"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.name
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title = "Requests and 5xx (ALB)", region = var.region, period = 60, stat = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.api.arn_suffix, "TargetGroup", aws_lb_target_group.api.arn_suffix],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", ".", ".", { color = "#d62728" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title = "Latency p50 / p95", region = var.region, period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.api.arn_suffix, "TargetGroup", aws_lb_target_group.api.arn_suffix, { stat = "p50" }],
            ["...", { stat = "p95" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 8, height = 6
        properties = {
          title   = "Healthy hosts", region = var.region, period = 60, stat = "Minimum"
          metrics = [["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", aws_lb.api.arn_suffix, "TargetGroup", aws_lb_target_group.api.arn_suffix]]
        }
      },
      {
        type = "metric", x = 8, y = 6, width = 8, height = 6
        properties = {
          title   = "CloudFront 5xx rate (%)", region = "us-east-1", period = 300, stat = "Average"
          metrics = [["AWS/CloudFront", "5xxErrorRate", "DistributionId", aws_cloudfront_distribution.web.id, "Region", "Global"]]
        }
      },
      {
        type = "alarm", x = 16, y = 6, width = 8, height = 6
        properties = {
          title = "Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.api_5xx_rate.arn,
            aws_cloudwatch_metric_alarm.api_latency_p95.arn,
            aws_cloudwatch_metric_alarm.no_healthy_hosts.arn,
            aws_cloudwatch_metric_alarm.edge_5xx_rate.arn,
          ]
        }
      },
      {
        type = "log", x = 0, y = 12, width = 24, height = 6
        properties = {
          title = "Recent 5xx by version", region = var.region
          query = "SOURCE '${aws_cloudwatch_log_group.api.name}' | filter msg = 'request' and status >= 500 | stats count() as errors by version, route | sort errors desc | limit 20"
          view  = "table"
        }
      },
    ]
  })
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${var.name}"
}
