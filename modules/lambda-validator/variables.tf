variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "backend_url" {
  description = "Backend API base URL"
  type        = string
  default     = "https://api-board.go-to-learn.net"
}

variable "backend_test_port" {
  description = "Backend test listener port"
  type        = string
  default     = "18443"
}

variable "tags" {
  description = "Tags for resources"
  type        = map(string)
  default     = {}
}
