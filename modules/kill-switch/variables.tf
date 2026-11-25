variable "project_id" {
  description = "Project that hosts the topic and function (the observability project)."
  type        = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "target_project_ids" {
  description = "Projects in which to stop labelled VMs and pause load-generator Scheduler jobs."
  type        = list(string)
}

variable "non_core_project_ids" {
  description = "Projects whose billing is detached when spend reaches detach_threshold. Never include the seed, platform or observability projects."
  type        = list(string)
}

variable "stop_threshold" {
  description = "Fraction of the budget at which load is stopped."
  type        = number
  default     = 0.9
}

variable "detach_threshold" {
  description = "Fraction of the budget at which billing is detached from non-core projects."
  type        = number
  default     = 1.0
}

variable "vm_label" {
  description = "VMs carrying this label key with value \"stop\" are stopped."
  type        = string
  default     = "kill-switch"
}

variable "scheduler_job_prefix" {
  description = "Cloud Scheduler jobs whose names start with this are paused."
  type        = string
  default     = "loadgen-"
}

variable "dry_run" {
  description = "When true the function logs what it would do and changes nothing. Turn off only after a test notification has been checked in the logs."
  type        = bool
  default     = true
}
