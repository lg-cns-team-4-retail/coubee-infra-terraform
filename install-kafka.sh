#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# Docker & Docker Compose 설치
apt-get update -y
apt-get install -y docker.io docker-compose

# Docker 자동 실행
systemctl enable docker
usermod -aG docker ubuntu

# Docker Compose 디렉토리 이동
cd /home/ubuntu

# docker-compose.yml 생성
cat <<EOF > docker-compose.yml
version: '3'
services:
  zookeeper1:
    image: confluentinc/cp-zookeeper:7.5.0
    container_name: zookeeper1
    ports:
      - "2181:2181"
    environment:
      ZOOKEEPER_SERVER_ID: 1
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
      ZOOKEEPER_INIT_LIMIT: 5
      ZOOKEEPER_SYNC_LIMIT: 2
      ZOOKEEPER_SERVERS: zookeeper1:2888:3888;zookeeper2:2888:3888;zookeeper3:2888:3888

  zookeeper2:
    image: confluentinc/cp-zookeeper:7.5.0
    container_name: zookeeper2
    ports:
      - "2182:2181"
    environment:
      ZOOKEEPER_SERVER_ID: 2
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
      ZOOKEEPER_INIT_LIMIT: 5
      ZOOKEEPER_SYNC_LIMIT: 2
      ZOOKEEPER_SERVERS: zookeeper1:2888:3888;zookeeper2:2888:3888;zookeeper3:2888:3888

  zookeeper3:
    image: confluentinc/cp-zookeeper:7.5.0
    container_name: zookeeper3
    ports:
      - "2183:2181"
    environment:
      ZOOKEEPER_SERVER_ID: 3
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
      ZOOKEEPER_INIT_LIMIT: 5
      ZOOKEEPER_SYNC_LIMIT: 2
      ZOOKEEPER_SERVERS: zookeeper1:2888:3888;zookeeper2:2888:3888;zookeeper3:2888:3888

  kafka1:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka1
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: "zookeeper1:2181,zookeeper2:2181,zookeeper3:2181"
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka1:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3

  kafka2:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka2
    ports:
      - "9093:9092"
    environment:
      KAFKA_BROKER_ID: 2
      KAFKA_ZOOKEEPER_CONNECT: "zookeeper1:2181,zookeeper2:2181,zookeeper3:2181"
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka2:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3

  kafka3:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka3
    ports:
      - "9094:9092"
    environment:
      KAFKA_BROKER_ID: 3
      KAFKA_ZOOKEEPER_CONNECT: "zookeeper1:2181,zookeeper2:2181,zookeeper3:2181"
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka3:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3

  kafdrop:
    image: obsidiandynamics/kafdrop:3.31.0
    container_name: kafdrop
    ports:
      - "9000:9000"
    environment:
      KAFKA_BROKERCONNECT: "kafka1:9092,kafka2:9092,kafka3:9092"
    depends_on:
      - kafka1
      - kafka2
      - kafka3
EOF

# docker-compose 실행
docker-compose up -d
