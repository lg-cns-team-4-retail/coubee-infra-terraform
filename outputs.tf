output "jenkins_public_ip" {
  value       = aws_instance.jenkins.public_ip
  description = "Jenkins EC2 퍼블릭 IP"
}

output "jenkins_instance_id" {
  value       = aws_instance.jenkins.id
  description = "Jenkins EC2 인스턴스 ID"
}

output "bastion_public_ip" {
  value       = aws_instance.bastion.public_ip
  description = "Bastion EC2 퍼블릭 IP"
}

output "bastion_instance_id" {
  value       = aws_instance.bastion.id
  description = "Bastion EC2 인스턴스 ID"
}

output "kafka_private_ip" {
  value       = aws_instance.kafka.private_ip
  description = "Kafka EC2 private IP"
}

output "kafka_instance_id" {
  value       = aws_instance.kafka.id
  description = "Kafka EC2 인스턴스 ID"
}

# output "cluster_name" {
#   value = module.eks.cluster_name
# }



output "vpc_id" {
  value       = aws_vpc.coubee.id
  description = "VPC ID"
}

output "subnet_public1_id" {
  value       = aws_subnet.public1.id
  description = "Public Subnet 1 ID"
}

output "subnet_private1_id" {
  value       = aws_subnet.private1.id
  description = "Private Subnet 1 ID"
}

output "subnet_private2_id" {
  value       = aws_subnet.private2.id
  description = "Private Subnet 2 ID"
}

output "nat_eip" {
  value       = aws_eip.nat.public_ip
  description = "Bastion EC2 퍼블릭 IP"
}

output "nat_gateway_id" {
  value       = aws_nat_gateway.nat.id
  description = "NAT Gateway ID"
}

output "igw_id" {
  value       = aws_internet_gateway.coubee.id
  description = "Internet Gateway ID"
}

output "public_route_table_id" {
  value       = aws_route_table.public.id
  description = "Public Route Table ID"
}
