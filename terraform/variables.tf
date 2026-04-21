variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
   default     = "1.29"
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
}

variable "node_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
}

variable "node_min_size" {
  description = "Minimum number of EKS nodes"
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database master username"
  type        = string
}

variable "my_ip" {
  description = "Your local machine public IP for SSH access"
  type        = string
}

variable "jenkins_instance_type" {
  description = "EC2 instance type for Jenkins server"
  type        = string
}

variable "sonarqube_instance_type" {
  description = "EC2 instance type for SonarQube server"
  type        = string
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
}

variable "public_key_path" {
  description = "Path to public key file for EC2 key pair"
  type        = string
}