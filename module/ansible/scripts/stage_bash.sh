#!/bin/bash
set -e  # Exit on any error

# =============================================
# SCRIPT CONFIGURATION VARIABLES
# =============================================
ASG_NAME="m3ap-main-stage-asg"               # Auto Scaling Group name
REGION="eu-west-2"                           # AWS region
INVENTORY_FILE="/etc/ansible/stage_hosts"    # Ansible inventory file
IP_LIST_FILE="/etc/ansible/stage_ips.txt"    # Temporary file to store discovered IPs
SSH_USER="ec2-user"                          # SSH user for RedHat instances
SSH_KEY_PATH="/home/ec2-user/.ssh/id_rsa"    # Path to SSH private key
DOCKER_REPO="nexus.example.com"              # Nexus Docker repository URL
DOCKER_USER="admin"                          # Docker repository username
DOCKER_PASSWORD="admin123"                   # Docker repository password
APP_IMAGE="$DOCKER_REPO/apppetclinic:latest" # Docker image name and tag

# =============================================
# SAFETY CHECKS & VALIDATION
# =============================================
echo "=== Starting Auto Scaling Group Management Script ==="
echo "Target ASG: $ASG_NAME"
echo "Region: $REGION"

# Check if required commands are available
for cmd in aws ssh ssh-keyscan; do
    if ! command -v $cmd &> /dev/null; then
        echo "ERROR: Required command '$cmd' not found. Please install it first."
        exit 1
    fi
done

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "ERROR: AWS CLI not configured. Please run 'aws configure' first."
    exit 1
fi

# Check if SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "ERROR: SSH key file '$SSH_KEY_PATH' not found."
    exit 1
fi

# Set proper permissions for SSH key
chmod 600 "$SSH_KEY_PATH"

# Validate AWS region
if ! aws ec2 describe-regions --region $REGION &> /dev/null; then
    echo "ERROR: Invalid AWS region '$REGION' or no access."
    exit 1
fi

# Check if we have write permissions for inventory files
if ! touch "$INVENTORY_FILE" 2>/dev/null; then
    echo "ERROR: Cannot write to inventory file '$INVENTORY_FILE'. Check permissions."
    exit 1
fi

if ! touch "$IP_LIST_FILE" 2>/dev/null; then
    echo "ERROR: Cannot write to IP list file '$IP_LIST_FILE'. Check permissions."
    exit 1
fi

# =============================================
# DISCOVER PRIVATE IP ADDRESSES FROM ASG
# =============================================
echo "=== Discovering instances in Auto Scaling Group: $ASG_NAME ==="

# Get instance IDs from Auto Scaling Group
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$REGION" \
    --query "AutoScalingGroups[0].Instances[].InstanceId" \
    --output text)

if [ -z "$INSTANCE_IDS" ] || [ "$INSTANCE_IDS" == "None" ]; then
    echo "ERROR: No instances found in Auto Scaling Group '$ASG_NAME'"
    echo "Please check if the ASG exists and has running instances."
    exit 1
fi

echo "Found instance IDs: $INSTANCE_IDS"

# Get private IP addresses
echo "=== Retrieving private IP addresses ==="
PRIVATE_IPS=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_IDS \
    --region "$REGION" \
    --query "Reservations[].Instances[].PrivateIpAddress" \
    --output text)

if [ -z "$PRIVATE_IPS" ]; then
    echo "ERROR: Could not retrieve private IP addresses"
    exit 1
fi

echo "Discovered private IPs: $PRIVATE_IPS"

# Count the number of instances
INSTANCE_COUNT=$(echo $PRIVATE_IPS | wc -w)
echo "Total instances discovered: $INSTANCE_COUNT"

# =============================================
# SAVE IP ADDRESSES TO FILE
# =============================================
echo "=== Saving IP addresses to $IP_LIST_FILE ==="
echo "$PRIVATE_IPS" | tr ' ' '\n' > "$IP_LIST_FILE"
echo "Successfully saved $INSTANCE_COUNT IP addresses to $IP_LIST_FILE"

# =============================================
# UPDATE ANSIBLE INVENTORY FILE
# =============================================
echo "=== Updating Ansible inventory file: $INVENTORY_FILE ==="

# Create backup of existing inventory file
if [ -f "$INVENTORY_FILE" ]; then
    BACKUP_FILE="${INVENTORY_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$INVENTORY_FILE" "$BACKUP_FILE"
    echo "Created backup of existing inventory: $BACKUP_FILE"
fi

# Create or overwrite the inventory file
cat > "$INVENTORY_FILE" << EOF
# Ansible inventory file for stage environment
# Auto-generated from ASG: $ASG_NAME
# Generated on: $(date)
# Total instances: $INSTANCE_COUNT

[webservers]
EOF

# Add each IP to the inventory file
for ip in $PRIVATE_IPS; do
    echo "$ip" >> "$INVENTORY_FILE"
    echo "Added $ip to [webservers] group"
done

# Add common variables for all webservers
cat >> "$INVENTORY_FILE" << EOF

[webservers:vars]
ansible_user=$SSH_USER
ansible_ssh_private_key_file=$SSH_KEY_PATH
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_become=yes
EOF

echo "Successfully updated Ansible inventory file: $INVENTORY_FILE"

# =============================================
# ADD HOSTS TO SSH KNOWN_HOSTS
# =============================================
echo "=== Adding hosts to SSH known_hosts ==="

for ip in $PRIVATE_IPS; do
    echo "Scanning SSH key for $ip..."
    if ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts 2>/dev/null; then
        echo "✓ Successfully added $ip to known_hosts"
    else
        echo "⚠ WARNING: Failed to add $ip to known_hosts (host may be unreachable)"
    fi
done

# =============================================
# CHECK AND MANAGE DOCKER CONTAINERS
# =============================================
echo "=== Checking and managing Docker containers on all instances ==="
echo "Target Docker image: $APP_IMAGE"

CONTAINER_RESTART_COUNT=0
UNREACHABLE_HOSTS=0

for ip in $PRIVATE_IPS; do
    echo "--- Processing instance: $ip ---"
    
    # Check if host is reachable
    if ! ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o BatchMode=yes "$SSH_USER@$ip" "echo 'Connection successful'" &>/dev/null; then
        echo "⚠ WARNING: Instance $ip is unreachable via SSH. Skipping..."
        UNREACHABLE_HOSTS=$((UNREACHABLE_HOSTS + 1))
        continue
    fi
    
    # Check if appContainer is running
    echo "Checking if appContainer is running on $ip..."
    
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 "$SSH_USER@$ip" \
        "sudo docker ps --filter 'name=appContainer' --format 'table {{.Names}}' | grep -q appContainer" 2>/dev/null; then
        
        echo "✓ appContainer is already running on $ip"
    else
        echo "✗ appContainer is NOT running on $ip"
        echo "Starting container deployment on $ip..."
        
        # Execute remote commands to deploy container
        if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=30 "$SSH_USER@$ip" << EOF
            set -e
            echo "Logging into Docker registry: $DOCKER_REPO"
            sudo docker login -u '$DOCKER_USER' -p '$DOCKER_PASSWORD' $DOCKER_REPO
            
            echo "Pulling latest Docker image: $APP_IMAGE"
            sudo docker pull '$APP_IMAGE'
            
            echo "Stopping and removing existing appContainer if present..."
            sudo docker stop appContainer 2>/dev/null || true
            sudo docker rm appContainer 2>/dev/null || true
            
            echo "Creating and starting new container..."
            sudo docker run -d \
                --name appContainer \
                -p 8080:8080 \
                --restart unless-stopped \
                '$APP_IMAGE'
            
            echo "Waiting for container to start..."
            sleep 10
            
            echo "Verifying container status..."
            sudo docker ps --filter name=appContainer --format "table {{.Names}}\t{{.Status}}"
            
            echo "Container deployment completed successfully"
EOF
        then
            echo "✓ Successfully deployed appContainer on $ip"
            CONTAINER_RESTART_COUNT=$((CONTAINER_RESTART_COUNT + 1))
        else
            echo "✗ FAILED to deploy appContainer on $ip"
        fi
    fi
    echo "--- Completed processing $ip ---"
    echo
done

# =============================================
# FINAL VERIFICATION
# =============================================
echo "=== Performing final verification ==="

RUNNING_CONTAINERS=0
for ip in $PRIVATE_IPS; do
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 "$SSH_USER@$ip" \
        "sudo docker ps --filter 'name=appContainer' --format 'table {{.Names}}' | grep -q appContainer" 2>/dev/null; then
        echo "✓ VERIFIED: appContainer running on $ip"
        RUNNING_CONTAINERS=$((RUNNING_CONTAINERS + 1))
    else
        echo "✗ WARNING: appContainer NOT running on $ip"
    fi
done

# =============================================
# SUMMARY REPORT
# =============================================
echo "=== SCRIPT EXECUTION SUMMARY ==="
echo "Auto Scaling Group: $ASG_NAME"
echo "Total instances discovered: $INSTANCE_COUNT"
echo "Instances with running containers: $RUNNING_CONTAINERS"
echo "Containers restarted: $CONTAINER_RESTART_COUNT"
echo "Unreachable hosts: $UNREACHABLE_HOSTS"
echo "Ansible inventory updated: $INVENTORY_FILE"
echo "IP list saved: $IP_LIST_FILE"

if [ $RUNNING_CONTAINERS -eq $INSTANCE_COUNT ]; then
    echo "🎉 SUCCESS: All instances have appContainer running!"
elif [ $RUNNING_CONTAINERS -eq 0 ]; then
    echo "❌ CRITICAL: No instances have appContainer running!"
    exit 1
else
    echo "⚠ WARNING: Only $RUNNING_CONTAINERS out of $INSTANCE_COUNT instances have appContainer running"
fi

echo "=== Script execution completed ==="