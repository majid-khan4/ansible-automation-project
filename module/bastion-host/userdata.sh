#!/bin/bash
# Bastion userdata: copy private key to ec2-user home, set permissions, install basic tools
set -eux

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

# Optionally install New Relic infrastructure agent if API key provided
if [ -n "${newrelic_api_key}" ] && [ -n "${newrelic_account_id}" ]; then
  # Install prerequisites
  yum update -y || true
  # Install New Relic Infrastructure agent (Linux/RHEL)
  curl -o /tmp/newrelic-infra.rpm -L https://download.newrelic.com/infrastructure_agent/linux/yum/el/7/x86_64/newrelic-infra-1.0.0-1.x86_64.rpm || true
  rpm -Uvh /tmp/newrelic-infra.rpm || true

  # Configure API key
  mkdir -p /etc/newrelic-infra
  cat > /etc/newrelic-infra.yml <<NR_CONF
license_key: ${newrelic_api_key}
account_id: ${newrelic_account_id}
NR_CONF

  systemctl enable newrelic-infra || true
  systemctl start newrelic-infra || true
fi

# Owner / Permissions final check
chown -R ec2-user:ec2-user /home/ec2-user

exit 0
