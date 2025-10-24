#!/bin/bash
set -eux

# ==============================
# Update system and install prerequisites
# ==============================
apt update -y
apt install -y openjdk-17-jdk wget unzip curl

# ==============================
# Create SonarQube user and directories
# ==============================
useradd -r -m -s /bin/bash sonarqube
mkdir -p /opt/sonarqube /opt/sonarqube/data
chown -R sonarqube:sonarqube /opt/sonarqube /opt/sonarqube/data

# ==============================
# Download and install SonarQube
# ==============================
wget "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-10.3.0.82913.zip" -O /tmp/sonarqube.zip
unzip /tmp/sonarqube.zip -d /opt/sonarqube --strip-components=1
chown -R sonarqube:sonarqube /opt/sonarqube
rm -f /tmp/sonarqube.zip

# ==============================
# Set Java environment
# ==============================
echo "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64" > /etc/profile.d/java.sh
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# ==============================
# Set system limits for SonarQube
# ==============================
echo "sonarqube   -   nofile   65536" >> /etc/security/limits.conf
echo "sonarqube   -   nproc    8192"  >> /etc/security/limits.conf

# ==============================
# Create systemd service for SonarQube
# ==============================
cat <<EOF > /etc/systemd/system/sonarqube.service
[Unit]
Description=SonarQube
After=network.target
After=syslog.target

[Service]
Type=forking
User=sonarqube
Group=sonarqube
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
Restart=always
RestartSec=10
LimitNOFILE=65536
LimitNPROC=8192
TimeoutStartSec=5min
Environment=JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start SonarQube
systemctl daemon-reload
systemctl enable sonarqube
systemctl start sonarqube

# ==============================
# Optional: Install New Relic (non-blocking)
# ==============================
(
  set +e
  curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash
  sudo NEW_RELIC_API_KEY="${newrelic_api_key}" \
       NEW_RELIC_ACCOUNT_ID="${newrelic_account_id}" \
       NEW_RELIC_REGION="EU" \
       /usr/local/bin/newrelic install -y
) &

# ==============================
# Set hostname
# ==============================
hostnamectl set-hostname sonarqube
