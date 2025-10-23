#!/bin/bash
set -eux

# Update system and install dependencies

yum install -y java-11-openjdk wget unzip  

# Install and start Amazon SSM Agent via snap
dnf install -y https://s3.eu-west-2.amazonaws.com/amazon-ssm-eu-west-2/latest/linux_amd64/amazon-ssm-agent.rpm

# Create nexus user and directories
useradd -r -m -s /bin/bash nexus 
mkdir -p /opt/nexus /opt/sonatype-work
chown -R nexus:nexus /opt/nexus /opt/sonatype-work

# Download and install Nexus Repository Manager (hardcoded version)
wget "https://download.sonatype.com/nexus/3/nexus-3.80.0-06-linux-x86_64.tar.gz" -O /tmp/nexus.tar.gz
tar -xzf /tmp/nexus.tar.gz -C /opt/nexus --strip-components=1
chown -R nexus:nexus /opt/nexus /opt/sonatype-work

# Adjust JVM memory
sed -i 's/^-Xms.*/-Xms512m/' /opt/nexus/bin/nexus.vmoptions
sed -i 's/^-Xmx.*/-Xmx512m/' /opt/nexus/bin/nexus.vmoptions

# Create systemd service for Nexus
cat <<EOF > /etc/systemd/system/nexus.service
[Unit]
Description=Nexus Repository Manager
After=network.target

[Service]
Type=forking
User=nexus
Group=nexus
ExecStart=/opt/nexus/bin/nexus start
ExecStop=/opt/nexus/bin/nexus stop
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Nexus
systemctl daemon-reload
systemctl enable nexus
systemctl start nexus

# Install New Relic
curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash && \
sudo NEW_RELIC_API_KEY="${newrelic_api_key}" \
NEW_RELIC_ACCOUNT_ID="${newrelic_account_id}" \
NEW_RELIC_REGION="EU" \
/usr/local/bin/newrelic install -y

# Set hostname
hostnamectl set-hostname nexus
