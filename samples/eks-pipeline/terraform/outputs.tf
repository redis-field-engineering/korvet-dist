# =============================================================================
# Outputs
# =============================================================================

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "s3_bucket_name" {
  description = "S3 bucket for Korvet tiered storage"
  value       = aws_s3_bucket.korvet_data.id
}

output "korvet_iam_role_arn" {
  description = "IAM role ARN for Korvet S3 access (use in ServiceAccount annotation)"
  value       = module.korvet_irsa.iam_role_arn
}

output "spark_iam_role_arn" {
  description = "IAM role ARN for Spark S3 access (use in ServiceAccount annotation)"
  value       = module.spark_irsa.iam_role_arn
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "s3_delta_path" {
  description = "S3 path for Korvet Delta Lake storage"
  value       = "s3a://${aws_s3_bucket.korvet_data.id}/korvet/delta"
}

output "s3_spark_output_path" {
  description = "S3 path for Spark Delta table output"
  value       = "s3a://${aws_s3_bucket.korvet_data.id}/spark/output"
}
