#!/bin/bash
set -euo pipefail
set -x  # Enable debug tracing

# ============================================================
# CONFIGURATION VARIABLES (PRODUCTION)
# ============================================================

ASG_NAME="m3ap-main-prod-asg"                   # Auto Scaling Group name for Prod
REGION="eu-west-2"                              # AWS region
INVENTORY_FILE="/etc/ansible/prod_hosts"        # Ansible inventory file for Prod
IP_LIST_FILE="/etc/ansible/prod_ips.txt"        # Temporary file to store discovered Prod IPs
SSH_USER="ec2-user"                             # SSH user for RedHat
SSH_KEY_PATH="/home/ec2-user/.ssh/id_rsa"       # SSH private key path
DOCKER_REPO="nexus.example.com"                 # Nexus Docker repository
DOCKER_USER="admin"                             # Docker repository username
DOCKER_PASSWORD="admin123"                      # Docker repository password
APP_IMAGE="$DOCKER_REPO/apppetclinic:latest"    # Docker image name and tag
WAIT_TIME=20                                    # Wait before SSH connections
AWSCLI_PATH="/usr/local/bin/aws"                # AWS CLI path

# ============================================================
# FUNCTIONS
# ============================================================

# 1️⃣ Discover private IPs of instances in the specified ASG
find_ips() {
    echo "🔍 Discovering private IPs for ASG: $ASG_NAME..."
    TMP_FILE=$(mktemp)

    $AWSCLI_PATH ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:aws:autoscaling:groupName,Values=$ASG_NAME" \
        --query 'Reservations[*].Instances[*].PrivateIpAddress' \
        --output text | tr '\t' '\n' | sort -u > "$TMP_FILE"

    # Idempotency: Update IP file only if changed
    if [ ! -f "$IP_LIST_FILE" ] || ! diff -q "$TMP_FILE" "$IP_LIST_FILE" >/dev/null; then
        mv "$TMP_FILE" "$IP_LIST_FILE"
        echo "✅ Updated IP list with new instances."
    else
        rm "$TMP_FILE"
        echo "ℹ️ No changes in instance IPs."
    fi
}

# 2️⃣ Update Ansible inventory with discovered IPs
update_inventory() {
    echo "🧩 Updating Ansible inventory: $INVENTORY_FILE..."
    TMP_INV=$(mktemp)
    echo "[webservers]" > "$TMP_INV"

    while IFS= read -r instance; do
        [ -z "$instance" ] && continue

        # Idempotency: add only if not already known
        if ! ssh-keygen -F "$instance" >/dev/null; then
            ssh-keyscan -H "$instance" >> ~/.ssh/known_hosts 2>/dev/null || true
        fi

        echo "$instance ansible_user=$SSH_USER" >> "$TMP_INV"
    done < "$IP_LIST_FILE"

    # Replace only if inventory changed
    if [ ! -f "$INVENTORY_FILE" ] || ! diff -q "$TMP_INV" "$INVENTORY_FILE" >/dev/null; then
        mv "$TMP_INV" "$INVENTORY_FILE"
        echo "✅ Inventory updated successfully."
    else
        rm "$TMP_INV"
        echo "ℹ️ Inventory already up-to-date."
    fi
}

# 3️⃣ Wait for instances to stabilize
wait_for_seconds() {
    echo "⏳ Waiting $WAIT_TIME seconds before connecting to instances..."
    sleep "$WAIT_TIME"
}

# 4️⃣ Check and manage Docker containers
check_docker_container() {
    echo "🐳 Checking Docker container status on all Prod instances..."
    while read -r ip; do
        [ -z "$ip" ] && continue
        echo "🔎 Checking host: $ip"

        # Check if appContainer exists and running
        container_status=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$SSH_USER@$ip" \
            "docker ps -a --filter 'name=appContainer' --format '{{.Status}}' || true")

        if echo "$container_status" | grep -q "Up"; then
            echo "✅ appContainer already running on $ip"
            continue
        fi

        echo "⚠️ appContainer not running on $ip — verifying image..."
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$SSH_USER@$ip" bash -s <<EOF
            set -e
            echo "🚀 Logging into Docker repo..."
            echo "$DOCKER_PASSWORD" | docker login "$DOCKER_REPO" -u "$DOCKER_USER" --password-stdin

            echo "📦 Checking if image $APP_IMAGE exists locally..."
            if ! docker image inspect "$APP_IMAGE" >/dev/null 2>&1; then
                echo "📥 Pulling latest image $APP_IMAGE..."
                docker pull "$APP_IMAGE"
            else
                echo "ℹ️ Image already present."
            fi

            echo "🧹 Removing any stopped container named appContainer..."
            docker rm -f appContainer >/dev/null 2>&1 || true

            echo "🛠️ Starting new container appContainer..."
            docker run -d --name appContainer -p 8080:8080 "$APP_IMAGE"

            echo "✅ appContainer started successfully on $(hostname)"
EOF
    done < "$IP_LIST_FILE"
}

# ============================================================
# MAIN FUNCTION
# ============================================================

main() {
    find_ips
    update_inventory
    wait_for_seconds
    check_docker_container
}

# ============================================================
# EXECUTION
# ============================================================

main