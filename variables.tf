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

// service
variable "project_id" {
  description = "The project ID to deploy to"
  type        = string
}

variable "service_name" {
  description = "The name of the Cloud Run service to create"
  type        = string
}

variable "location" {
  description = "Cloud Run service deployment location"
  type        = string
}

variable "generate_revision_name" {
  type        = bool
  description = "Option to enable revision name generation"
  default     = true
}

variable "traffic_split" {
  type = list(object({
    latest_revision = bool
    percent         = number
    revision_name   = string
    tag             = string
  }))
  description = "Managing traffic routing to the service"
  default = [{
    latest_revision = true
    percent         = 100
    revision_name   = "v1-0-0"
    tag             = null
  }]
}

variable "service_labels" {
  type        = map(string)
  description = "A set of key/value label pairs to assign to the service"
  default     = {}
}

variable "service_annotations" {
  type        = map(string)
  description = "Annotations to the service. Acceptable values all, internal, internal-and-cloud-load-balancing"
  default = {
    "run.googleapis.com/ingress" = "all"
  }
}

// Metadata
variable "template_labels" {
  type        = map(string)
  description = "A set of key/value label pairs to assign to the container metadata"
  default     = {}
}

variable "template_annotations" {
  type        = map(string)
  description = "Annotations to the container metadata including VPC Connector and SQL. See [more details](https://cloud.google.com/run/docs/reference/rpc/google.cloud.run.v1#revisiontemplate)"
  default = {
    "run.googleapis.com/client-name"   = "terraform"
    "generated-by"                     = "terraform"
    "autoscaling.knative.dev/maxScale" = 2
    "autoscaling.knative.dev/minScale" = 1
  }
}

variable "encryption_key" {
  description = "CMEK encryption key self-link expected in the format projects/PROJECT/locations/LOCATION/keyRings/KEY-RING/cryptoKeys/CRYPTO-KEY."
  type        = string
  default     = null
}

// template spec
variable "container_concurrency" {
  type        = number
  description = "Concurrent request limits to the service"
  default     = null
}

variable "timeout_seconds" {
  type        = number
  description = "Timeout for each request"
  default     = 120
}

variable "service_account_email" {
  type        = string
  description = "Service Account email needed for the service"
  default     = ""
}

variable "volumes" {
  type = list(object({
    name = string
    secret = set(object({
      secret_name = string
      items       = map(string)
    }))
  }))
  description = "[Beta] Volumes needed for environment variables (when using secret)"
  default     = []
}

variable "containers" {
  type = list(object({
    # Name of the container
    name = optional(string, null)
    # GCR hosted image URL to deploy
    image = optional(string, null)
    # Resource limits to the container
    limits = optional(map(string), null)
    # Resource requests to the container
    requests = optional(map(string), null)
    # Port which the container listens to (http1 or h2c)
    ports = optional(object({
      name = string
      port = number
    }), null)
    # Arguments passed to the ENTRYPOINT command, include these only if image entrypoint needs arguments
    argument = optional(list(string), null)
    # Leave blank to use the ENTRYPOINT command defined in the container image, include these only if image entrypoint should be overwritten
    command = optional(list(string), null)
    # Startup probe of application within the container.
    # All other probes are disabled if a startup probe is provided, until it succeeds.
    # Container will not be added to service endpoints if the probe fails.
    # More info: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle#container-probes
    startup_probe = optional(object({
      failure_threshold     = optional(number, null)
      initial_delay_seconds = optional(number, null)
      timeout_seconds       = optional(number, null)
      period_seconds        = optional(number, null)
      http_get = optional(object({
        path = optional(string)
        http_headers = optional(list(object({
          name  = string
          value = string
        })), null)
      }), null)
      tcp_socket = optional(object({
        port = optional(number)
      }), null)
      grpc = optional(object({
        port    = optional(number)
        service = optional(string)
      }), null)
    }), null)
    # Periodic probe of container liveness. Container will be restarted if the probe fails.
    # More info: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle#container-probes
    liveness_probe = optional(object({
      failure_threshold     = optional(number, null)
      initial_delay_seconds = optional(number, null)
      timeout_seconds       = optional(number, null)
      period_seconds        = optional(number, null)
      http_get = optional(object({
        path = optional(string)
        http_headers = optional(list(object({
          name  = string
          value = string
        })), null)
      }), null)
      grpc = optional(object({
        port    = optional(number)
        service = optional(string)
      }), null)
    }), null)
    # Environment variables (cleartext)
    env_vars = optional(list(object({
      value = string
      name  = string
    })), null)
    # [Beta] Environment variables (Secret Manager)
    env_secret_vars = optional(list(object({
      name = string
      value_from = set(object({
        secret_key_ref = map(string)
      }))
    })), null)
    # [Beta] Volume Mounts to be attached to the container (when using secret)
    volume_mounts = optional(list(object({
      mount_path = string
      name       = string
    })), null)
  }))
  default     = null
  description = <<-EOF
    Containers Definitions
    More info: https://cloud.google.com/run/docs/reference/yaml/v1
  EOF
}

// Domain Mapping
variable "verified_domain_name" {
  type        = list(string)
  description = "List of Custom Domain Name"
  default     = []
}

variable "force_override" {
  type        = bool
  description = "Option to force override existing mapping"
  default     = false
}

variable "certificate_mode" {
  type        = string
  description = "The mode of the certificate (NONE or AUTOMATIC)"
  default     = "NONE"
}

variable "domain_map_labels" {
  type        = map(string)
  description = "A set of key/value label pairs to assign to the Domain mapping"
  default     = {}
}

variable "domain_map_annotations" {
  type        = map(string)
  description = "Annotations to the domain map"
  default     = {}
}

// IAM
variable "members" {
  type        = list(string)
  description = "Users/SAs to be given invoker access to the service"
  default     = []
}
