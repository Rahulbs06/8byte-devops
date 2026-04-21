module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "security_groups" {
  source = "./modules/security-groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
  jenkins_sg_id  = module.jenkins_server.jenkins_sg_id
}

module "eks" {
  source = "./modules/eks"

  project_name       = var.project_name
  environment        = var.environment
  cluster_version    = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  eks_cluster_sg_id  = module.security_groups.eks_cluster_sg_id
  eks_nodes_sg_id    = module.security_groups.eks_nodes_sg_id
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
}

module "rds" {
  source = "./modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  rds_sg_id          = module.security_groups.rds_sg_id
  db_instance_class  = var.db_instance_class
  db_name            = var.db_name
  db_username        = var.db_username
}

module "jenkins_server" {
  source = "./modules/jenkins-server"

  project_name            = var.project_name
  environment             = var.environment
  vpc_id                  = module.vpc.vpc_id
  public_subnet_id        = module.vpc.public_subnet_ids[0]
  my_ip                   = var.my_ip
  jenkins_instance_type   = var.jenkins_instance_type
  sonarqube_instance_type = var.sonarqube_instance_type
  key_name                = var.key_name
  public_key_path         = var.public_key_path
}