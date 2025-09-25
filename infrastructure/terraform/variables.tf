variable "project" {
  description = "Project identifier used for naming resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment label (e.g. dev, prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "input_bucket_name" {
  description = "Optional override for the input bucket name"
  type        = string
  default     = null
}

variable "output_bucket_name" {
  description = "Optional override for the output bucket name"
  type        = string
  default     = null
}

variable "sns_topic_name" {
  description = "Optional override for the SNS topic name"
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC identifier used by the Batch compute environment"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Batch compute environment"
  type        = list(string)
}

variable "batch_min_vcpus" {
  description = "Minimum vCPUs for the Batch compute environment"
  type        = number
  default     = 0
}

variable "batch_max_vcpus" {
  description = "Maximum vCPUs for the Batch compute environment"
  type        = number
  default     = 256
}

variable "batch_desired_vcpus" {
  description = "Desired vCPUs for the Batch compute environment"
  type        = number
  default     = 0
}

variable "batch_instance_types" {
  description = "Instance types allowed for the Batch compute environment"
  type        = list(string)
  default     = ["g4dn.xlarge", "g5.xlarge"]
}

variable "batch_spot_bid_percentage" {
  description = "Maximum percentage of on-demand price for spot instances"
  type        = number
  default     = 70
}

variable "batch_job_image" {
  description = "Container image URI that includes Ollama and the runner script"
  type        = string
}

variable "ollama_model" {
  description = "Default Ollama model to execute"
  type        = string
  default     = "llama2"
}

variable "job_vcpus" {
  description = "Default vCPU allocation per job"
  type        = number
  default     = 4
}

variable "job_memory" {
  description = "Default memory (MiB) allocation per job"
  type        = number
  default     = 16384
}

variable "job_timeout_seconds" {
  description = "Default timeout in seconds for submitted jobs"
  type        = number
  default     = 3600
}

variable "default_prompt_file" {
  description = "Default prompt file name to read from the input payload"
  type        = string
  default     = "prompt.txt"
}

variable "default_output_file" {
  description = "Default output file name when prompt does not specify"
  type        = string
  default     = "output.txt"
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention period"
  type        = number
  default     = 30
}

variable "default_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
