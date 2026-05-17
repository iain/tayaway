variable "ovh_endpoint" {
  description = "OVH API endpoint — `ovh-eu` for the European control plane (default for tayaway)."
  type        = string
  default     = "ovh-eu"
}

variable "service_name" {
  description = "OVH public cloud project ID (the long hex string in the OVH manager URL)."
  type        = string
}

variable "region_name" {
  description = "OVH region for the state bucket — `GRA`, `SBG`, or `DE`. Use the same region as the WAL-G bucket to keep things simple."
  type        = string
  default     = "GRA"
}

variable "bucket_name" {
  description = "Name of the state bucket. Globally unique within OVH Object Storage; change if a previous tayaway deploy already owns this name."
  type        = string
  default     = "tayaway-tfstate"
}
