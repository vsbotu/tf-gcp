variable "project_id" {
  type        = string
  description = "GCP project ID where resources are created."
}

variable "region" {
  type        = string
  description = "GCP region (e.g. us-east1)."
  default     = "us-east1"
}

variable "zone" {
  type        = string
  description = "GCP zone for zonal GKE cluster (e.g. us-east1-b)."
  default     = "us-east1-b"
}

variable "network_name" {
  type        = string
  description = "Name of the custom VPC."
  default     = "gke-vpc"
}

variable "subnet_name" {
  type        = string
  description = "Name of the GKE subnet."
  default     = "gke-vpc-us-east1"
}

variable "subnet_ip_cidr_range" {
  type        = string
  description = "Primary IPv4 CIDR for nodes (must not overlap pod/service ranges)."
  default     = "10.0.0.0/20"
}

variable "pods_secondary_range_name" {
  type        = string
  description = "Subnet secondary range name for cluster pod IPs (alias IP)."
  default     = "pods"
}

variable "pods_ip_cidr_range" {
  type        = string
  description = "CIDR for pods (secondary range on the subnet)."
  default     = "10.42.0.0/17"
}

variable "services_secondary_range_name" {
  type        = string
  description = "Subnet secondary range name for Services (ClusterIP)."
  default     = "services"
}

variable "services_ip_cidr_range" {
  type        = string
  description = "CIDR for Kubernetes services (secondary range on the subnet)."
  default     = "10.100.0.0/20"
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name."
  default     = "gke-us-east1"
}

variable "release_channel" {
  type        = string
  description = "GKE release channel: UNSPECIFIED, RAPID, REGULAR, or STABLE."
  default     = "REGULAR"
}

variable "gateway_api_channel" {
  type        = string
  description = "Gateway API channel: CHANNEL_STANDARD, CHANNEL_EXPERIMENTAL, or CHANNEL_DISABLED."
  default     = "CHANNEL_STANDARD"
}

variable "node_pool_name" {
  type        = string
  description = "Primary node pool name."
  default     = "default-pool"
}

variable "node_count" {
  type        = number
  description = "Initial node count in the primary pool."
  default     = 2
}

variable "machine_type" {
  type        = string
  description = "Machine type for nodes (e.g. e2-medium, e2-small)."
  default     = "e2-medium"
}

variable "disk_size_gb" {
  type        = number
  description = "Boot disk size per node (GB)."
  default     = 50
}

variable "deletion_protection" {
  type        = bool
  description = "Enable cluster deletion protection (set false for labs)."
  default     = false
}
