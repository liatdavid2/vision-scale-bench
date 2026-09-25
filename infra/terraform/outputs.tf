output "cluster_name" { value = module.eks.cluster_name }
output "region" { value = var.aws_region }
output "crossplane_role_arn" { value = aws_iam_role.crossplane.arn }
output "sagemaker_role_arn" { value = aws_iam_role.sagemaker.arn }
output "account_id" { value = data.aws_caller_identity.current.account_id }
