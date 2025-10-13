#!/bin/bash
set -e

# ==============================
# System preparation
# ==============================
apt update -y
apt upgrade -y
apt install -y unzip jq curl wget lsb-release apt-transport-https gpg

# ==============================
# Install Vault (Latest Stable Version)
# ==============================
VAULT_VERSION="1.18.3"
echo "Installing Vault ${VAULT_VERSION}..."

# Download Vault binary
wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip

# Unzip and move Vault to PATH
unzip vault_${VAULT_VERSION}_linux_amd64.zip
sudo mv vault /usr/local/bin/
sudo chown root:root /usr/local/bin/vault
sudo chmod 0755 /usr/local/bin/vault

# Verify installation
vault --version

# ==============================
# Create Vault user and directories
# ==============================
sudo useradd --system --home /etc/vault.d --shell /bin/false vault
sudo mkdir -p /etc/vault.d /var/lib/vault
sudo chown -R vault:vault /etc/vault.d /var/lib/vault

# ==============================
# Vault configuration file
# ==============================
cat <<EOF | sudo tee /etc/vault.d/vault.hcl
storage "file" {
  path = "/var/lib/vault"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

seal "awskms" {
  region     = "${region}"
  kms_key_id = "${key}"
}

ui = true
EOF

sudo chown vault:vault /etc/vault.d/vault.hcl
sudo chmod 640 /etc/vault.d/vault.hcl

# ==============================
# Create systemd service
# ==============================
cat <<EOF | sudo tee /etc/systemd/system/vault.service
[Unit]
Description=HashiCorp Vault - Secrets Management
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
StartLimitInterval=60
StartLimitBurst=3
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault

# ==============================
# Configure environment
# ==============================
export VAULT_ADDR='http://127.0.0.1:8200'
echo "export VAULT_ADDR='http://127.0.0.1:8200'" | sudo tee /etc/profile.d/vault.sh
echo "export VAULT_SKIP_VERIFY=true" | sudo tee -a /etc/profile.d/vault.sh

# Wait for Vault to initialize
sleep 20

# ==============================
# Initialize and unseal Vault
# ==============================
vault operator init -key-shares=1 -key-threshold=1 > /home/ubuntu/vault_init.log
grep -o 'hvs\.[A-Za-z0-9]\{24\}' /home/ubuntu/vault_init.log > /home/ubuntu/token.txt
TOKEN=$(cat /home/ubuntu/token.txt)

# Login
vault login $TOKEN

# ==============================
# Enable KV secrets engine and save DB credentials
# ==============================
vault secrets enable -path=secret kv

# Store database credentials securely in Vault
vault kv put secret/database username="petclinic" password="petclinic"

# ==============================
# Verification and Final Steps
# ==============================
vault status
sudo hostnamectl set-hostname Vault

echo "✅ Vault installation and configuration complete."