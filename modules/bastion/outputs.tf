output "instance_id" {
  description = "Bastion EC2 instance ID. Connect via AWS Console -> EC2 -> Connect -> Session Manager."
  value       = aws_instance.bastion.id
}

output "iam_role_arn" {
  description = "Bastion IAM role ARN. The root stack grants this an EKS access entry so kubectl works."
  value       = aws_iam_role.bastion.arn
}

output "connect_hint" {
  description = "How to open a shell on the bastion."
  value       = "AWS Console -> Systems Manager -> Session Manager -> Start session -> ${aws_instance.bastion.id}"
}
