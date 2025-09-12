# Terraform


클라우드 인프라 관리 자동화를 위한 테라폼 코드입니다.
************


### 인프라 아키텍처
*********


<img width="3780" height="2638" alt="인프라 구성도_To-Be" src="https://github.com/user-attachments/assets/1b98d974-e414-49a4-bf95-ef04160cd01d" />


### 자동화된 리소스
***********
● VPC
● Bastion
● ELB
● Jenkins
● Lambda
● Kafka
● ECR
● ElasticCache for Valkey
● RDS for PostgreSQL
● EventBridge
● EC2 (Python)


### 시작
**********
1. terraform 프로젝트 초기화
    terraform init


2. 리소스 생성 계획
    terraform plan


3. 리소스 생성
    terraform apply


4. 리소스 삭제
    terraform destory
