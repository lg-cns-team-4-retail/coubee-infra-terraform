# # EKS Cluster
# resource "aws_eks_cluster" "eks_cluster" {
#   name     = "${var.project_name}_eks_cluster"
#   role_arn = aws_iam_role.eks_cluster_role.arn
#   version  = "1.33"

#   vpc_config {
#     subnet_ids         = [aws_subnet.private1.id, aws_subnet.private2.id] 
#     security_group_ids = [aws_security_group.eks_cluster_sg.id]
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
#     aws_iam_role_policy_attachment.eks_cluster_AmazonEKSBlockStoragePolicy,
#     aws_iam_role_policy_attachment.eks_cluster_AmazonEKSComputePolicy,
#     aws_iam_role_policy_attachment.eks_cluster_AmazonEKSLoadBalancingPolicy,
#     aws_iam_role_policy_attachment.eks_cluster_AmazonEKSNetworkingPolicy
#   ]
# }

# # Launch Template for Node Group
# resource "aws_launch_template" "eks_node_lt" {
#   name_prefix   = "${var.project_name}_eks_node_"
#   instance_type = "t3a.medium"
#   key_name = var.key_name

#   block_device_mappings {
#     device_name = "/dev/xvda"
#     ebs {
#       volume_size           = 20
#       volume_type           = "gp3"
#       delete_on_termination = true
#     }
#   }

#   vpc_security_group_ids = [aws_security_group.eks_node_sg.id]

#   tag_specifications {
#     resource_type = "instance"
#     tags = {
#       Name = "${var.project_name}_eks_node"
#     }
#   }
# }

# # Node Group
# resource "aws_eks_node_group" "eks_node_group" {
#   cluster_name    = aws_eks_cluster.eks_cluster.name
#   node_group_name = "${var.project_name}_eks_node_group"
#   node_role_arn   = aws_iam_role.eks_node_role.arn
#   subnet_ids      = [aws_subnet.private1.id]



#   scaling_config {
#     desired_size = 6
#     max_size     = 6
#     min_size     = 6
#   }

#   launch_template {
#     id      = aws_launch_template.eks_node_lt.id
#     version = "$Latest"
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.eks_worker_node_minimal_policy,
#     aws_iam_role_policy_attachment.eks_worker_node_cni_policy,
#     aws_iam_role_policy_attachment.eks_worker_node_ecr_pull_only
#   ]
# }

resource "aws_ecr_repository" "gateway" {
  name = "coubee-be-gateway"
  force_delete = true
}

resource "aws_ecr_repository" "user" {
  name = "coubee-be-user"
  force_delete = true
}

resource "aws_ecr_repository" "product" {
  name = "coubee-be-product"
  force_delete = true
}

resource "aws_ecr_repository" "store" {
  name = "coubee-be-store"
  force_delete = true
}

resource "aws_ecr_repository" "notification" {
  name = "coubee-be-notification"
  force_delete = true
}

resource "aws_ecr_repository" "order" {
  name = "coubee-be-order"
  force_delete = true
}

resource "aws_ecr_repository" "elasticsearch" {
  name = "coubee-infra-elasticsearch"
  force_delete = true
}

resource "aws_ecr_repository" "logstash" {
  name = "coubee-infra-logstash"
  force_delete = true
}

resource "aws_ecr_repository" "kibana" {
  name = "coubee-infra-kibana"
  force_delete = true
}