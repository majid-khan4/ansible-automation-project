#!/bin/bash
# Bastion userdata: copy private key to ec2-user home, set permissions, install basic tools
set -eux

# Install and start Amazon SSM Agent first for troubleshooting access
echo "[bastion-userdata] Installing amazon-ssm-agent"
yum install -y https://s3.${region}.amazonaws.com/amazon-ssm-${region}/latest/linux_amd64/amazon-ssm-agent.rpm

# Enable and start the service
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
echo "[bastion-userdata] amazon-ssm-agent status: $(systemctl is-active amazon-ssm-agent)"

SSH_DIR="/home/ec2-user/.ssh"
PRIVATE_KEY_PATH="$SSH_DIR/id_rsa"

# Ensure the ec2-user exists (RHEL AMIs usually have ec2-user)
if ! id ec2-user >/dev/null 2>&1; then
  # fallback to ec2-user creation if necessary
  useradd -m -s /bin/bash ec2-user || true
fi

mkdir -p "$SSH_DIR"
chown ec2-user:ec2-user "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Write private key (passed as variable)
cat > "$PRIVATE_KEY_PATH" <<'KEY_EOF'
${private_key_pem}
KEY_EOF

chown ec2-user:ec2-user "$PRIVATE_KEY_PATH"
chmod 600 "$PRIVATE_KEY_PATH"

# Install New Relic
curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash && \
sudo NEW_RELIC_API_KEY="${newrelic_api_key}" \
NEW_RELIC_ACCOUNT_ID="${newrelic_account_id}" \
NEW_RELIC_REGION="EU" \
/usr/local/bin/newrelic install -y

# Owner / Permissions final check
chown -R ec2-user:ec2-user /home/ec2-user

exit 0
