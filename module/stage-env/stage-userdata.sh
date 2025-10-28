#!/bin/bash
set -eux

# --- Update the system ---
sudo dnf update -y

# --- Install dependencies ---
sudo dnf install -y yum-utils curl git

# --- Add Docker repository ---
sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

# --- Install Docker and dependencies ---
sudo dnf install -y docker-ce docker-ce-cli containerd.io

# --- Start and enable Docker service ---
sudo systemctl start docker
sudo systemctl enable docker

# --- Add ec2-user to docker group ---
sudo usermod -aG docker ec2-user

# --- Verify Docker installation ---
docker --version

# --- Install New Relic agent ---
# Replace ${NEW_RELIC_API_KEY} and ${NEW_RELIC_ACCOUNT_ID} using Terraform variables
curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash
sudo NEW_RELIC_API_KEY="${NEW_RELIC_API_KEY}" NEW_RELIC_ACCOUNT_ID="${NEW_RELIC_ACCOUNT_ID}" /usr/local/bin/newrelic install -y

# --- Set hostname for identification ---
sudo hostnamectl set-hostname stage