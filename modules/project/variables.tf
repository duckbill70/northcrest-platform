variable "project_id" {
  description = "Globally unique project ID."
  type        = string
}

variable "name" {
  description = "Display name."
  type        = string
}

variable "folder_id" {
  description = "Parent folder, as returned by google_folder.folder_id (numeric) or name (folders/123)."
  type        = string
}

variable "billing_account_id" {
  description = "Billing account to link. Null leaves the project unbilled."
  type        = string
  default     = null
}

variable "services" {
  description = "APIs to enable."
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Project labels. Used by cost reports and the kill switch."
  type        = map(string)
  default     = {}
}

variable "deletion_policy" {
  description = "PREVENT blocks terraform destroy on this project; DELETE allows it (used for time-boxed demo projects)."
  type        = string
  default     = "PREVENT"
}
