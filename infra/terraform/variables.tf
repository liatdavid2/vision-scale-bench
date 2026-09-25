variable "aws_region" { type = string; default = "eu-central-1" }
variable "cluster_name" { type = string; default = "vision-scale-bench" }
variable "worker_count" {
  type = number
  default = 2
  validation {
    condition = contains([0, 1, 2, 4], var.worker_count)
    error_message = "worker_count must be 0, 1, 2 or 4 for this GPU benchmark."
  }
}
variable "instance_types" {
  type = list(string)
  default = ["g4dn.xlarge"]
}
