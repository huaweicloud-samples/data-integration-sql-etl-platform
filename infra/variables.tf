variable "region" {
  description = "华为云区域"
  type        = string
  default     = "cn-north-4"
}

variable "project_name" {
  description = "项目名称前缀"
  type        = string
  default     = "spark-etl"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "jhub_secret_password" {
  description = "JupyterHub 登录密码（由 DEW CSMS 托管）"
  type        = string
  sensitive   = true
  default     = "REPLACE_WITH_STRONG_PASSWORD"
}

variable "node_password" {
  description = "CCE 节点 root 登录密码（生产建议改用 key_pair）"
  type        = string
  sensitive   = true
  default     = "Spark-Etl@2026"
}
