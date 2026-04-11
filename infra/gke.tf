resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone

  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.gke.name
  subnetwork      = google_compute_subnetwork.gke.name

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  release_channel {
    channel = var.release_channel
  }

  gateway_api_config {
    channel = var.gateway_api_channel
  }

  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection

  depends_on = [
    google_project_service.container,
    google_compute_subnetwork.gke,
  ]
}

resource "google_container_node_pool" "primary" {
  name     = var.node_pool_name
  location = var.zone
  cluster  = google_container_cluster.primary.name

  initial_node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-balanced"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  depends_on = [
    google_container_cluster.primary,
  ]
}
