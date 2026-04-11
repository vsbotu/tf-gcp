output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.gke.name
}

output "subnet_name" {
  description = "Subnet name."
  value       = google_compute_subnetwork.gke.name
}

output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.primary.name
}

output "cluster_location" {
  description = "Zonal location of the cluster (zone)."
  value       = google_container_cluster.primary.location
}

output "get_credentials_command" {
  description = "Run this to configure kubectl."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${var.zone} --project ${var.project_id}"
}

output "verify_gateway_api_command" {
  description = "After credentials, confirm Gateway API classes exist."
  value       = "kubectl get gatewayclass"
}
