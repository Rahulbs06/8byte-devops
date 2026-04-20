output "s3_bucket_name" {
   description = "S3 bucket name in backend configuration"
   value       = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table_name" {
   description = "DynamoDB table name in backend configuration"
   value       = aws_dynamodb_table.terraform_lock.name
}

output "s3_buckut_arn" {
    description = "ARN of the state bucket"
    value       = aws_s3_bucket.terraform_state.arn 
}