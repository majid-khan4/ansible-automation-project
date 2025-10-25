#!/bin/bash
set -e
# Update instance and dependencies for RHEL based instances 
sudo dnf update -y
sudo dnf install unzip wget git python3-pip -y
sudo bash -c 'echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config'

#install awscli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
sudo ln -svf /usr/local/bin/aws /usr/bin/aws

# Install Ansible and related tools
sudo dnf install -y ansible-core
sudo pip3 install boto3 botocore

# Install Ansible AWS collection
sudo ansible-galaxy collection install amazon.aws

# Create ansible user if not exists
sudo useradd -m ansible || true

# Setup SSH directory for ansible user
sudo mkdir -p /home/ansible/.ssh
sudo chmod 700 /home/ansible/.ssh

# Copy private key into ansible user home
sudo bash -c 'echo "${private_key_pem}" > /home/ansible/.ssh/id_rsa'
sudo chmod 400 /home/ansible/.ssh/id_rsa
sudo chown ansible:ansible /home/ansible/.ssh/id_rsa

# copying our file to ansible server
sudo mkdir -p /home/ansible/playbooks

#pulling playbooks from s3 bucket
sudo aws s3 cp s3://"${s3_bucket}"/playbooks/ /home/ansible/playbooks/ --recursive

sleep 10

# create ansible variables file
sudo bash -c 'echo "NEXUS_IP: ${nexus_ip}:8085" > /etc/ansible/ansible_vars.yml'
sudo chown ansible:ansible /etc/ansible/ansible_vars.yml
sudo chmod 755 /etc/ansible/prod-bashscript.sh
sudo chmod 755 /etc/ansible/stage-bashscript.sh

# Create cron job using our bash script
echo "* * * * * ansible /etc/ansible/prod-bashscript.sh" | sudo tee -a /etc/crontab
echo "* * * * * ansible /etc/ansible/stage-bashscript.sh" | sudo tee -a /etc/crontab

# Set proper ownership for ansible directories
sudo chown -R ansible:ansible /home/ansible/playbooks
sudo chmod 755 /home/ansible/playbooks

#install new relic
curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash && sudo NEW_RELIC_API_KEY="${newrelic_api_key}" NEW_RELIC_ACCOUNT_ID="${newrelic_account_id}" NEW_RELIC_REGION=EU /usr/local/bin/newrelic install -y

