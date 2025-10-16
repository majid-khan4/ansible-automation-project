#!/bin/bash
set -eux

# Update system and install dependencies
yum update -y
yum install -y java-11-openjdk wget unzip amazon-ssm-agent

# Enable and start SSM Agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Create nexus user and directories
useradd nexus
mkdir -p /opt/nexus /opt/sonatype-work
wget https://download.sonatype.com/nexus/3/nexus-3.80.0-06-linux-x86_64.tar.gz
tar -xzvf nexus-3.80.0-06-linux-x86_64.tar.gz -C /opt/nexus --strip-components=1
chown -R nexus:nexus /opt/nexus /opt/sonatype-work

# Adjust memory settings
sed -i '2s/-Xms2703m/-Xms512m/' /opt/nexus/bin/nexus.vmoptions
sed -i '3s/-Xmx2703m/-Xmx512m/' /opt/nexus/bin/nexus.vmoptions

# Create systemd service
cat <<EOL > /etc/systemd/system/nexus.service
[Unit]
Description=Nexus
After=network.target

[Service]
Type=forking
User=nexus
Group=nexus
ExecStart=/opt/nexus/bin/nexus start
ExecStop=/opt/nexus/bin/nexus stop
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOL

# Enable and start Nexus
systemctl daemon-reexec
systemctl enable nexus
systemctl start nexus

# Set hostname
hostnamectl set-hostname nexus
