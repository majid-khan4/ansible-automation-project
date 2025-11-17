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

# --- Configure Docker daemon for insecure registry using nexus_ip variable ---
sudo mkdir -p /etc/docker

cat <<EOF | sudo tee /etc/docker/daemon.json > /dev/null
{
  "insecure-registries": ["${nexus_ip}:8085"]
}
EOF

# --- Reload systemd and restart Docker ---
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl enable docker

# --- Add ec2-user to docker group ---
sudo usermod -aG docker ec2-user

# --- Verify Docker installation ---
docker --version

# --- Install New Relic agent ---
curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash && \
sudo NEW_RELIC_API_KEY="${newrelic_api_key}" \
NEW_RELIC_ACCOUNT_ID="${newrelic_account_id}" \
NEW_RELIC_REGION="EU" \
/usr/local/bin/newrelic install -y

# --- Set hostname for identification ---
sudo hostnamectl set-hostname stage
