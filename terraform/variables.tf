variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-1"
}

variable "queue_count" {
  description = "Number of SQS queues to create and subscribe to the SNS topic"
  type        = number
  default     = 3
}

variable "queue_name_prefix" {
  description = "Prefix for SQS queue names"
  type        = string
  default     = "fanout-queue"
}
