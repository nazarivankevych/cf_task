# Create a bucket
# Upload function.zip --> +
# Deploy function --> +
# create a trigger
# policy binding

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.44.1"
    }
  # }
  # backend "gcp" {
  #   prefix = "/task-cf"
  # }
  }
}

provider "google" {
  # Configuration options
  project = var.project_id
  region = var.region
  zone = var.zone
}

resource "google_storage_bucket" "task-cf-bucket" {
  name = "${var.project_id}-bucket"
  location = var.region
  force_destroy = true
}

data "archive_file" "source" {
  type        = "zip"
  source_dir = "./function"
  output_path = "/tmp/function.zip"
}

resource "google_storage_bucket_object" "zip" {
  source = data.archive_file.source.output_path
  content_type = "application/zip"
  name = "src-${data.archive_file.source.output_md5}.zip"
  bucket = google_storage_bucket.task-cf-bucket.name

  depends_on = [
    google_storage_bucket.task-cf-bucket,
    data.archive_file.source
  ]
}

resource "google_cloudfunctions_function" "task-cf-function" {
  name = "task-cf-function"
  runtime             = "python38"

  source_archive_bucket = google_storage_bucket.task-cf-bucket.name
  source_archive_object = google_storage_bucket_object.zip.name
  
  entry_point         = "main"
  trigger_http = true
  
  available_memory_mb = 128
  timeout = 60

  depends_on = [
    google_bigquery_dataset.task-cf-dataset,
    google_storage_bucket.task-cf-bucket,
    google_storage_bucket_object.zip
  ]
}

resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.task-cf-function.project
  region         = google_cloudfunctions_function.task-cf-function.region
  cloud_function = google_cloudfunctions_function.task-cf-function.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"

  depends_on = [
    google_cloudfunctions_function.task-cf-function
  ]
}

resource "google_bigquery_dataset" "task-cf-dataset" {
  dataset_id  = var.dataset_id
  description = "This dataset is public"
  location    = "US"
}

resource "google_bigquery_table" "task-cf-table" {
  dataset_id = var.dataset_id
  table_id   = var.table_id
  schema     = file("/task-cf/schemas/bq_table_schema/task-cf-raw.json")

  depends_on = [
    google_bigquery_dataset.task-cf-dataset
  ]
}

