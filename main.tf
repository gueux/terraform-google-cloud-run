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
          image   = containers.value.image
          command = containers.value.container_command
          args    = containers.value.argument

          dynamic "ports" {
            for_each = containers.value.ports != null ? [containers.value.ports] : []
            content {
              name           = ports.value.name
              container_port = ports.value.port
            }
          }

          resources {
            limits   = containers.value.limits
            requests = containers.value.requests
          }

          dynamic "startup_probe" {
            for_each = containers.value.startup_probe != null ? [containers.value.startup_probe] : []
            content {
              failure_threshold     = startup_probe.value.failure_threshold
              initial_delay_seconds = startup_probe.value.initial_delay_seconds
              timeout_seconds       = startup_probe.value.timeout_seconds
              period_seconds        = startup_probe.value.period_seconds
              dynamic "http_get" {
                for_each = startup_probe.value.http_get != null ? [1] : []
                content {
                  path = http_get.value.path
                  dynamic "http_headers" {
                    for_each = http_get.value.http_headers != null ? http_get.value.http_headers : []
                    content {
                      name  = http_headers.value.name
                      value = http_headers.value.value
                    }
                  }
                }
              }
              dynamic "tcp_socket" {
                for_each = startup_probe.value.tcp_socket != null ? [startup_probe.value.tcp_socket] : []
                content {
                  port = tcp_socket.value.port
                }
              }
              dynamic "grpc" {
                for_each = startup_probe.value.grpc != null ? [startup_probe.value.grpc] : []
                content {
                  port    = grpc.port
                  service = grpc.service
                }
              }
            }
          }

          dynamic "liveness_probe" {
            for_each = containers.value.liveness_probe != null ? [containers.value.liveness_probe] : []
            content {
              failure_threshold     = liveness_probe.value.failure_threshold
              initial_delay_seconds = liveness_probe.value.initial_delay_seconds
              timeout_seconds       = liveness_probe.value.timeout_seconds
              period_seconds        = liveness_probe.value.period_seconds
              dynamic "http_get" {
                for_each = liveness_probe.value.http_get != null ? [1] : []
                content {
                  path = http_get.value.path
                  dynamic "http_headers" {
                    for_each = http_get.value.http_headers != null ? http_get.value.http_headers : []
                    content {
                      name  = http_headers.value["name"]
                      value = http_headers.value["value"]
                    }
                  }
                }
              }
              dynamic "grpc" {
                for_each = liveness_probe.value.grpc != null ? [liveness_probe.value.grpc] : []
                content {
                  port    = grpc.port
                  service = grpc.service
                }
              }
            }
          }

          dynamic "env" {
            for_each = containers.value.env_vars != null ? containers.value.env_vars : []
            content {
              name  = env.value["name"]
              value = env.value["value"]
            }
          }

          dynamic "env" {
            for_each = containers.value.env_secret_vars != null ? containers.value.env_secret_vars : []
            content {
              name = env.value.name
              dynamic "value_from" {
                for_each = env.value["value_from"]
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
            for_each = containers.value.volume_mounts != null ? containers.value.volume_mounts : []
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
