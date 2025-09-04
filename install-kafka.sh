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
    ports: ["2181:2181"]
    environment:
      ZOOKEEPER_SERVER_ID: 1
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
      ZOOKEEPER_INIT_LIMIT: 5
      ZOOKEEPER_SYNC_LIMIT: 2
      ZOOKEEPER_SERVERS: zookeeper1:2888:3888;zookeeper2:2888:3888;zookeeper3:2888:3888
    networks:
      - kafka-network
  zookeeper2:
    image: confluentinc/cp-zookeeper:7.5.0
    container_name: zookeeper2
    ports: ["2182:2181"]
    environment:
      ZOOKEEPER_SERVER_ID: 2
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
      ZOOKEEPER_INIT_LIMIT: 5
      ZOOKEEPER_SYNC_LIMIT: 2
      ZOOKEEPER_SERVERS: zookeeper1:2888:3888;zookeeper2:2888:3888;zookeeper3:2888:3888
    networks:
      - kafka-network
  zookeeper3:
    image: confluentinc/cp-zookeeper:7.5.0
    container_name: zookeeper3
    ports: ["2183:2181"]
    environment:
      ZOOKEEPER_SERVER_ID: 3
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
      ZOOKEEPER_INIT_LIMIT: 5
      ZOOKEEPER_SYNC_LIMIT: 2
      ZOOKEEPER_SERVERS: zookeeper1:2888:3888;zookeeper2:2888:3888;zookeeper3:2888:3888
    networks:
      - kafka-network
  kafka1:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka1
    depends_on:
      - zookeeper1
      - zookeeper2
      - zookeeper3
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: "zookeeper1:2181,zookeeper2:2181,zookeeper3:2181"
      KAFKA_LISTENERS: INTERNAL://0.0.0.0:19092,EXTERNAL://0.0.0.0:9092
      KAFKA_ADVERTISED_LISTENERS: INTERNAL://kafka1:19092,EXTERNAL://10.0.2.254:9092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: INTERNAL
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
      KAFKA_MIN_INSYNC_REPLICAS: 2
      # 추가 설정으로 안정성 향상
      KAFKA_DEFAULT_REPLICATION_FACTOR: 3
      KAFKA_NUM_PARTITIONS: 3
      KAFKA_LOG_RETENTION_HOURS: 168
    networks:
      - kafka-network
    healthcheck:
      test: ["CMD-SHELL", "kafka-broker-api-versions --bootstrap-server localhost:9092"]
      interval: 30s
      timeout: 10s
      retries: 3
  kafka2:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka2
    depends_on:
      - zookeeper1
      - zookeeper2
      - zookeeper3
    ports:
      - "9093:9092"
    environment:
      KAFKA_BROKER_ID: 2
      KAFKA_ZOOKEEPER_CONNECT: "zookeeper1:2181,zookeeper2:2181,zookeeper3:2181"
      KAFKA_LISTENERS: INTERNAL://0.0.0.0:19092,EXTERNAL://0.0.0.0:9092
      KAFKA_ADVERTISED_LISTENERS: INTERNAL://kafka2:19092,EXTERNAL://10.0.2.254:9093
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: INTERNAL
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
      KAFKA_MIN_INSYNC_REPLICAS: 2
      KAFKA_DEFAULT_REPLICATION_FACTOR: 3
      KAFKA_NUM_PARTITIONS: 3
      KAFKA_LOG_RETENTION_HOURS: 168
    networks:
      - kafka-network
    healthcheck:
      test: ["CMD-SHELL", "kafka-broker-api-versions --bootstrap-server localhost:9092"]
      interval: 30s
      timeout: 10s
      retries: 3
  kafka3:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka3
    depends_on:
      - zookeeper1
      - zookeeper2
      - zookeeper3
    ports:
      - "9094:9092"
    environment:
      KAFKA_BROKER_ID: 3
      KAFKA_ZOOKEEPER_CONNECT: "zookeeper1:2181,zookeeper2:2181,zookeeper3:2181"
      KAFKA_LISTENERS: INTERNAL://0.0.0.0:19092,EXTERNAL://0.0.0.0:9092
      KAFKA_ADVERTISED_LISTENERS: INTERNAL://kafka3:19092,EXTERNAL://10.0.2.254:9094
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: INTERNAL
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
      KAFKA_MIN_INSYNC_REPLICAS: 2
      KAFKA_DEFAULT_REPLICATION_FACTOR: 3
      KAFKA_NUM_PARTITIONS: 3
      KAFKA_LOG_RETENTION_HOURS: 168
    networks:
      - kafka-network
    healthcheck:
      test: ["CMD-SHELL", "kafka-broker-api-versions --bootstrap-server localhost:9092"]
      interval: 30s
      timeout: 10s
      retries: 3
  kafdrop:
    image: obsidiandynamics/kafdrop:3.31.0
    container_name: kafdrop
    ports: ["9000:9000"]
    environment:
      KAFKA_BROKERCONNECT: "kafka1:19092,kafka2:19092,kafka3:19092"
    depends_on:
      kafka1:
        condition: service_healthy
      kafka2:
        condition: service_healthy
      kafka3:
        condition: service_healthy
    networks:
      - kafka-network
networks:
  kafka-network:
    driver: bridge
EOF

# docker-compose 실행
docker-compose up -d
