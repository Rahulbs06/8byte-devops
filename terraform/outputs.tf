output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.eks.ecr_repository_url
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_endpoint
}


output "jenkins_public_ip" {
  description = "Jenkins server public IP"
  value       = module.jenkins_server.jenkins_public_ip
}

output "sonarqube_public_ip" {
  description = "SonarQube server public IP"
  value       = module.jenkins_server.sonarqube_public_ip
}