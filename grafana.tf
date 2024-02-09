terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = ">= 1.28.2"
    }
  }
}
provider "grafana" {
  url  = "http://localhost:3000"
  auth = "eyJrIjoiZGlrT29TeTdUaGt6dEpFTGNjODVMSW1RVVhoNzhPWm0iLCJuIjoidGVzdCIsImlkIjoxfQ=="
}


resource "grafana_contact_point" "my_contact_point" {
  name = "Send to PagerDuty Channel"
  pagerduty {
    integration_key = "7f93a6f3a8c24c0cc00cb0584c47e43"
    summary         = <<EOT
{{ len .Alerts.Firing }} alerts are firing!
Alert summaries:
{{ range .Alerts.Firing }}
{{ template "channel_alerts_pagerduty_title" . }}
{{ end }}
EOT
  }
}

resource "grafana_notification_policy" "my_policy" {
  group_by      = ["alertname"]
  contact_point = "Send to PagerDuty Channel"
  policy {
    matcher {
      label = "notification"
      match = "="
      value = "channel_alerts"
    }
    contact_point = "Send to PagerDuty Channel"
    group_by      = ["..."]
  }
  policy {
    matcher {
      label = "alertname"
      match = "="
      value = "My Random Walk Alert"
    }
    contact_point = "Send to PagerDuty Channel"
    group_by      = ["..."]
  }
}

/*resource "grafana_message_template" "my_alert_template" {
    name = "Alert Instance Template"

    template = <<EOT
{{ define "Alert Instance Template" }}
Firing: {{ .Labels.alertname }}
Silence: {{ .SilenceURL }}
{{ end }}
EOT
}*/

resource "grafana_message_template" "channel_alerts_pagerduty_title" {
  name = "Alert Instance Template"

  template = <<EOT
{{ define "channel.alerts.pagerduty.title" }}
{{ if eq .Status "firing" }}Identified{{ else if eq .Status "resolved" }}Resolved{{ end }} - {{ .CommonAnnotations.summary }}
{{ end }}
EOT
}


resource "grafana_data_source" "testdata_datasource" {
  name = "TestData"
  type = "testdata"
}

resource "grafana_folder" "rule_folder" {
  title = "My Rule Folder"
}

resource "grafana_rule_group" "my_rule_group" {
  name             = "My Alert Rules"
  folder_uid       = grafana_folder.rule_folder.uid
  interval_seconds = 60

  rule {
    name      = "My Random Walk Alert"
        labels = {
        notification = "channel_alerts"
      }
    condition = "C"
    for       = "0s"

    // Query the datasource.
    data {
      ref_id = "A"
      relative_time_range {
        from = 600
        to   = 0
      }
      datasource_uid = grafana_data_source.testdata_datasource.uid
      // `model` is a JSON blob that sends datasource-specific data.
      // It's different for every datasource. The alert's query is defined here.
      model = jsonencode({
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "A"
      })

    }

    // The query was configured to obtain data from the last 60 seconds. Let's alert on the average value of that series using a Reduce stage.
    data {
      datasource_uid = "__expr__"
      // You can also create a rule in the UI, then GET that rule to obtain the JSON.
      // This can be helpful when using more complex reduce expressions.
      model  = <<EOT
{"conditions":[{"evaluator":{"params":[0,0],"type":"gt"},"operator":{"type":"and"},"query":{"params":["A"]},"reducer":{"params":[],"type":"last"},"type":"avg"}],"datasource":{"name":"Expression","type":"__expr__","uid":"__expr__"},"expression":"A","hide":false,"intervalMs":1000,"maxDataPoints":43200,"reducer":"last","refId":"B","type":"reduce"}
EOT
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
    }

    // Now, let's use a math expression as our threshold.
    // We want to alert when the value of stage "B" above exceeds 70.
    data {
      datasource_uid = "__expr__"
      ref_id         = "C"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        expression = "$B > 70"
        type       = "math"
        refId      = "C"
      })
    }
  }
}
