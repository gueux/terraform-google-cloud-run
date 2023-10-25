/**
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  cmek_template_annotation = var.encryption_key != null ? { "run.googleapis.com/encryption-key" = var.encryption_key } : {}
  template_annotations     = merge(var.template_annotations, local.cmek_template_annotation)
}

resource "google_cloud_run_service" "main" {
  provider                   = google-beta
  name                       = var.service_name
  location                   = var.location
  project                    = var.project_id
  autogenerate_revision_name = var.generate_revision_name

  metadata {
    labels      = var.service_labels
    annotations = var.service_annotations
  }

  template {
    spec {
      container_concurrency = var.container_concurrency # maximum allowed concurrent requests 0,1,2-N
      timeout_seconds       = var.timeout_seconds       # max time instance is allowed to respond to a request
      service_account_name  = var.service_account_email

      dynamic "containers" {
        for_each = var.containers
        content {
          image   = containers.image
          command = containers.container_command
          args    = containers.argument

          ports {
            name           = containers.ports["name"]
            container_port = containers.ports["port"]
          }

          resources {
            limits   = containers.limits
            requests = containers.requests
          }

          dynamic "startup_probe" {
            for_each = containers.startup_probe != null ? [1] : []
            content {
              failure_threshold     = containers.startup_probe.failure_threshold
              initial_delay_seconds = containers.startup_probe.initial_delay_seconds
              timeout_seconds       = containers.startup_probe.timeout_seconds
              period_seconds        = containers.startup_probe.period_seconds
              dynamic "http_get" {
                for_each = containers.startup_probe.http_get != null ? [1] : []
                content {
                  path = containers.startup_probe.http_get.path
                  dynamic "http_headers" {
                    for_each = containers.startup_probe.http_get.http_headers != null ? containers.startup_probe.http_get.http_headers : []
                    content {
                      name  = http_headers.value["name"]
                      value = http_headers.value["value"]
                    }
                  }
                }
              }
              dynamic "tcp_socket" {
                for_each = containers.startup_probe.tcp_socket != null ? [1] : []
                content {
                  port = containers.startup_probe.tcp_socket.port
                }
              }
              dynamic "grpc" {
                for_each = containers.startup_probe.grpc != null ? [1] : []
                content {
                  port    = containers.startup_probe.grpc.port
                  service = containers.startup_probe.grpc.service
                }
              }
            }
          }

          dynamic "liveness_probe" {
            for_each = containers.liveness_probe != null ? [1] : []
            content {
              failure_threshold     = containers.liveness_probe.failure_threshold
              initial_delay_seconds = containers.liveness_probe.initial_delay_seconds
              timeout_seconds       = containers.liveness_probe.timeout_seconds
              period_seconds        = containers.liveness_probe.period_seconds
              dynamic "http_get" {
                for_each = containers.liveness_probe.http_get != null ? [1] : []
                content {
                  path = containers.liveness_probe.http_get.path
                  dynamic "http_headers" {
                    for_each = containers.liveness_probe.http_get.http_headers != null ? containers.liveness_probe.http_get.http_headers : []
                    content {
                      name  = http_headers.value["name"]
                      value = http_headers.value["value"]
                    }
                  }
                }
              }
              dynamic "grpc" {
                for_each = containers.liveness_probe.grpc != null ? [1] : []
                content {
                  port    = containers.liveness_probe.grpc.port
                  service = containers.liveness_probe.grpc.service
                }
              }
            }
          }

          dynamic "env" {
            for_each = containers.env_vars
            content {
              name  = env.value["name"]
              value = env.value["value"]
            }
          }

          dynamic "env" {
            for_each = containers.env_secret_vars
            content {
              name = env.value["name"]
              dynamic "value_from" {
                for_each = env.value.value_from
                content {
                  secret_key_ref {
                    name = value_from.value.secret_key_ref["name"]
                    key  = value_from.value.secret_key_ref["key"]
                  }
                }
              }
            }
          }

          dynamic "volume_mounts" {
            for_each = containers.volume_mounts
            content {
              name       = volume_mounts.value["name"]
              mount_path = volume_mounts.value["mount_path"]
            }
          }
        } // container
      }

      dynamic "volumes" {
        for_each = var.volumes
        content {
          name = volumes.value["name"]
          dynamic "secret" {
            for_each = volumes.value.secret
            content {
              secret_name = secret.value["secret_name"]
              items {
                key  = secret.value.items["key"]
                path = secret.value.items["path"]
              }
            }
          }
        }
      }

    } // spec
    metadata {
      labels      = var.template_labels
      annotations = local.template_annotations
      name        = var.generate_revision_name ? null : "${var.service_name}-${var.traffic_split[0].revision_name}"
    } // metadata
  }   // template

  # User can generate multiple scenarios here
  # Providing 50-50 split with revision names
  # latest_revision is true only when revision_name is not provided, else its false
  dynamic "traffic" {
    for_each = var.traffic_split
    content {
      percent         = lookup(traffic.value, "percent", 100)
      latest_revision = lookup(traffic.value, "latest_revision", null)
      revision_name   = lookup(traffic.value, "latest_revision") ? null : lookup(traffic.value, "revision_name")
      tag             = lookup(traffic.value, "tag", null)
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["client.knative.dev/user-image"],
      metadata[0].annotations["run.googleapis.com/client-name"],
      metadata[0].annotations["run.googleapis.com/client-version"],
      metadata[0].annotations["run.googleapis.com/operation-id"],
      template[0].metadata[0].annotations["client.knative.dev/user-image"],
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
      template[0].metadata[0].annotations["run.googleapis.com/client-version"],
    ]
  }
}

resource "google_cloud_run_domain_mapping" "domain_map" {
  for_each = toset(var.verified_domain_name)
  provider = google-beta
  location = google_cloud_run_service.main.location
  name     = each.value
  project  = google_cloud_run_service.main.project

  metadata {
    labels      = var.domain_map_labels
    annotations = var.domain_map_annotations
    namespace   = var.project_id
  }

  spec {
    route_name       = google_cloud_run_service.main.name
    force_override   = var.force_override
    certificate_mode = var.certificate_mode
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["run.googleapis.com/operation-id"],
    ]
  }
}

resource "google_cloud_run_service_iam_member" "authorize" {
  count    = length(var.members)
  location = google_cloud_run_service.main.location
  project  = google_cloud_run_service.main.project
  service  = google_cloud_run_service.main.name
  role     = "roles/run.invoker"
  member   = var.members[count.index]
}
