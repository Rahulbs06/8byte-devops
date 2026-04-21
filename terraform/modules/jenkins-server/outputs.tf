output "jenkins_public_ip" {
  description = "Jenkins EC2 public IP"
  value       = aws_instance.jenkins.public_ip
}

output "sonarqube_public_ip" {
  description = "SonarQube EC2 public IP"
  value       = aws_instance.sonarqube.public_ip
}

output "jenkins_sg_id" {
  description = "Jenkins security group ID"
  value       = aws_security_group.jenkins.id
}