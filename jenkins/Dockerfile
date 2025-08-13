FROM jenkins/jenkins:lts-jdk17

USER root

# docker 설치
RUN apt-get update && apt-get install -y docker.io

# docker 그룹이 없을 경우에만 추가
RUN getent group docker || groupadd -g 999 docker
RUN usermod -aG docker jenkins

# awscli 설치 (apt로 설치)
RUN apt-get update && \
    apt-get install -y unzip curl awscli && \
    apt-get clean

USER jenkins
