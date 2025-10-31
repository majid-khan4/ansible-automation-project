#!/bin/bash
set -e  # Exit on any error

# =============================================
# SCRIPT CONFIGURATION VARIABLES - PRODUCTION
# =============================================
ASG_NAME="m3ap-main-prod-asg"                  # Production Auto Scaling Group name
REGION="eu-west-2"                             # AWS region
INVENTORY_FILE="/etc/ansible/prod_hosts"       # Production Ansible inventory file
IP_LIST_FILE="/etc/ansible/prod_ips.txt"       # Temporary file to store discovered IPs
BACKUP_DIR="/etc/ansible/backups"              # Backup directory for inventory files
LOG_FILE="/var/log/prod_container_manager.log" # Log file for auditing
SSH_USER="ec2-user"                            # SSH user for RedHat instances
SSH_KEY_PATH="/home/ec2-user/.ssh/id_rsa"      # Path to SSH private key
DOCKER_REPO="nexus.example.com"                # Nexus Docker repository URL
DOCKER_USER="admin"                            # Docker repository username
DOCKER_PASSWORD="admin123"                     # Docker repository password
APP_IMAGE="$DOCKER_REPO/apppetclinic:latest"   # Docker image name and tag
MAX_PARALLEL_SSH=5                             # Limit parallel SSH connections for production safety
DRY_RUN=false                                  # Set to true to preview changes without executing

# =============================================
# LOGGING SETUP
# =============================================
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# =============================================
# SAFETY CHECKS & VALIDATION - PRODUCTION GRADE
# =============================================
echo "=== PRODUCTION Auto Scaling Group Management Script ==="
log_message "INFO" "Script started for ASG: $ASG_NAME in region: $REGION"

# Check if required commands are available
for cmd in aws ssh ssh-keyscan; do
    if ! command -v $cmd &> /dev/null; then
        log_message "ERROR" "Required command '$cmd' not found"
        echo "ERROR: Required command '$cmd' not found. Please install it first."
        exit 1
    fi
done

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    log_message "ERROR" "AWS CLI not properly configured"
    echo "ERROR: AWS CLI not configured. Please run 'aws configure' first."
    exit 1
fi

# Check if SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    log_message "ERROR" "SSH key file '$SSH_KEY_PATH' not found"
    echo "ERROR: SSH key file '$SSH_KEY_PATH' not found."
    exit 1
fi

# Set proper permissions for SSH key
chmod 600 "$SSH_KEY_PATH"

# Validate AWS region
if ! aws ec2 describe-regions --region $REGION &> /dev/null; then
    log_message "ERROR" "Invalid AWS region '$REGION' or no access"
    echo "ERROR: Invalid AWS region '$REGION' or no access."
    exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"
chmod 755 "$BACKUP_DIR"

# Check if we have write permissions for inventory files
if ! touch "$INVENTORY_FILE" 2>/dev/null; then
    log_message "ERROR" "Cannot write to inventory file '$INVENTORY_FILE'"
    echo "ERROR: Cannot write to inventory file '$INVENTORY_FILE'. Check permissions."
    exit 1
fi

if ! touch "$IP_LIST_FILE" 2>/dev/null; then
    log_message "ERROR" "Cannot write to IP list file '$IP_LIST_FILE'"
    echo "ERROR: Cannot write to IP list file '$IP_LIST_FILE'. Check permissions."
    exit 1
fi

# =============================================
# DRY RUN WARNING
# =============================================
if [ "$DRY_RUN" = true ]; then
    echo "⚠️  DRY RUN MODE - No changes will be made"
    log_message "WARNING" "Script running in DRY RUN mode - no changes will be executed"
fi

# =============================================
# DISCOVER PRIVATE IP ADDRESSES FROM ASG
# =============================================
echo "=== Discovering instances in Production Auto Scaling Group: $ASG_NAME ==="
log_message "INFO" "Starting instance discovery for ASG: $ASG_NAME"

# Get instance IDs from Auto Scaling Group
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$REGION" \
    --query "AutoScalingGroups[0].Instances[].InstanceId" \
    --output text)

if [ -z "$INSTANCE_IDS" ] || [ "$INSTANCE_IDS" == "None" ]; then
    log_message "ERROR" "No instances found in Auto Scaling Group '$ASG_NAME'"
    echo "ERROR: No instances found in Production Auto Scaling Group '$ASG_NAME'"
    echo "This is PRODUCTION - please verify the ASG exists and has running instances."
    exit 1
fi

echo "Found instance IDs: $INSTANCE_IDS"
log_message "INFO" "Discovered instance IDs: $INSTANCE_IDS"

# Get private IP addresses
echo "=== Retrieving private IP addresses ==="
PRIVATE_IPS=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_IDS \
    --region "$REGION" \
    --query "Reservations[].Instances[].PrivateIpAddress" \
    --output text)

if [ -z "$PRIVATE_IPS" ]; then
    log_message "ERROR" "Could not retrieve private IP addresses"
    echo "ERROR: Could not retrieve private IP addresses"
    exit 1
fi

echo "Discovered private IPs: $PRIVATE_IPS"
log_message "INFO" "Discovered private IPs: $PRIVATE_IPS"

# Count the number of instances
INSTANCE_COUNT=$(echo $PRIVATE_IPS | wc -w)
echo "Total production instances discovered: $INSTANCE_COUNT"
log_message "INFO" "Total production instances discovered: $INSTANCE_COUNT"

# =============================================
# SAVE IP ADDRESSES TO FILE
# =============================================
echo "=== Saving IP addresses to $IP_LIST_FILE ==="
echo "$PRIVATE_IPS" | tr ' ' '\n' > "$IP_LIST_FILE"
echo "Successfully saved $INSTANCE_COUNT IP addresses to $IP_LIST_FILE"
log_message "INFO" "Saved $INSTANCE_COUNT IP addresses to $IP_LIST_FILE"

# =============================================
# UPDATE ANSIBLE INVENTORY FILE WITH BACKUP
# =============================================
echo "=== Updating Production Ansible inventory file: $INVENTORY_FILE ==="

# Create comprehensive backup of existing inventory file
if [ -f "$INVENTORY_FILE" ]; then
    BACKUP_FILE="${BACKUP_DIR}/prod_hosts.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$INVENTORY_FILE" "$BACKUP_FILE"
    echo "Created backup of production inventory: $BACKUP_FILE"
    log_message "INFO" "Created backup of production inventory: $BACKUP_FILE"
fi

# Create or overwrite the inventory file
if [ "$DRY_RUN" = false ]; then
    cat > "$INVENTORY_FILE" << EOF
# PRODUCTION Ansible inventory file
# Auto-generated from ASG: $ASG_NAME
# Generated on: $(date)
# Total instances: $INSTANCE_COUNT
# DO NOT EDIT MANUALLY - This file is auto-generated

[prod_webservers]
EOF

    # Add each IP to the inventory file
    for ip in $PRIVATE_IPS; do
        echo "$ip" >> "$INVENTORY_FILE"
        echo "Added $ip to [prod_webservers] group"
        log_message "INFO" "Added $ip to production inventory"
    done

    # Add common variables for all production webservers
    cat >> "$INVENTORY_FILE" << EOF

[prod_webservers:vars]
ansible_user=$SSH_USER
ansible_ssh_private_key_file=$SSH_KEY_PATH
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_become=yes
environment=production
EOF

    echo "Successfully updated Production Ansible inventory file: $INVENTORY_FILE"
    log_message "INFO" "Updated production inventory file with $INSTANCE_COUNT hosts"
else
    echo "DRY RUN: Would update inventory file with $INSTANCE_COUNT hosts"
fi

# =============================================
# ADD HOSTS TO SSH KNOWN_HOSTS
# =============================================
echo "=== Adding production hosts to SSH known_hosts ==="

for ip in $PRIVATE_IPS; do
    echo "Scanning SSH key for production host $ip..."
    if ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts 2>/dev/null; then
        echo "✓ Successfully added production host $ip to known_hosts"
        log_message "INFO" "Added production host $ip to known_hosts"
    else
        echo "⚠ WARNING: Failed to add production host $ip to known_hosts"
        log_message "WARNING" "Failed to add production host $ip to known_hosts"
    fi
done

# =============================================
# CHECK AND MANAGE DOCKER CONTAINERS - PRODUCTION
# =============================================
echo "=== Checking and managing Docker containers on Production instances ==="
echo "Target Docker image: $APP_IMAGE"
log_message "INFO" "Starting container management for $INSTANCE_COUNT production instances"

CONTAINER_RESTART_COUNT=0
UNREACHABLE_HOSTS=0
FAILED_DEPLOYMENTS=0

# Function to process a single host
process_production_host() {
    local ip=$1
    local host_log="/tmp/prod_host_${ip//./_}.log"
    
    {
        echo "--- Processing PRODUCTION instance: $ip ---"
        log_message "INFO" "Starting processing of production instance: $ip"
        
        # Check if host is reachable
        if ! ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o BatchMode=yes "$SSH_USER@$ip" "echo 'Production connection successful'" &>/dev/null; then
            echo "❌ CRITICAL: Production instance $ip is unreachable via SSH"
            log_message "ERROR" "Production instance $ip is unreachable via SSH"
            return 1
        fi
        
        # Check if appContainer is running
        echo "Checking if appContainer is running on production instance $ip..."
        
        if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 "$SSH_USER@$ip" \
            "sudo docker ps --filter 'name=appContainer' --format 'table {{.Names}}' | grep -q appContainer" 2>/dev/null; then
            
            echo "✅ PRODUCTION VERIFIED: appContainer running on $ip"
            log_message "INFO" "Production instance $ip has appContainer running"
            return 0
        else
            echo "🔄 PRODUCTION DEPLOYMENT: appContainer not running on $ip"
            log_message "WARNING" "Production instance $ip needs container deployment"
            
            if [ "$DRY_RUN" = true ]; then
                echo "DRY RUN: Would deploy appContainer to production instance $ip"
                return 0
            fi
            
            # Execute remote commands to deploy container in production
            if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=30 "$SSH_USER@$ip" << EOF
                set -e
                echo "PRODUCTION: Logging into Docker registry: $DOCKER_REPO"
                sudo docker login -u '$DOCKER_USER' -p '$DOCKER_PASSWORD' $DOCKER_REPO
                
                echo "PRODUCTION: Pulling Docker image: $APP_IMAGE"
                sudo docker pull '$APP_IMAGE'
                
                echo "PRODUCTION: Stopping and removing existing appContainer..."
                sudo docker stop appContainer 2>/dev/null || true
                sudo docker rm appContainer 2>/dev/null || true
                
                echo "PRODUCTION: Creating and starting new container..."
                sudo docker run -d \
                    --name appContainer \
                    -p 8080:8080 \
                    --restart unless-stopped \
                    --log-driver json-file \
                    --log-opt max-size=10m \
                    --log-opt max-file=3 \
                    '$APP_IMAGE'
                
                echo "PRODUCTION: Waiting for container to start..."
                sleep 15
                
                echo "PRODUCTION: Verifying container status..."
                sudo docker ps --filter name=appContainer --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                
                echo "PRODUCTION: Checking container health..."
                sudo docker inspect --format='{{.State.Status}}' appContainer
                
                echo "PRODUCTION: Container deployment completed successfully"
EOF
            then
                echo "✅ SUCCESS: Deployed appContainer on production instance $ip"
                log_message "INFO" "Successfully deployed appContainer on production instance $ip"
                return 0
            else
                echo "❌ FAILED: Deployment failed on production instance $ip"
                log_message "ERROR" "Failed to deploy appContainer on production instance $ip"
                return 1
            fi
        fi
    } >> "$host_log" 2>&1
}

# Export function for parallel processing
export -f process_production_host
export SSH_KEY_PATH SSH_USER DRY_RUN DOCKER_REPO DOCKER_USER DOCKER_PASSWORD APP_IMAGE LOG_FILE

# Process hosts with limited parallelism for production safety
echo "Processing production instances with max parallelism: $MAX_PARALLEL_SSH"
for ip in $PRIVATE_IPS; do
    while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL_SSH ]; do
        sleep 1
    done
    process_production_host "$ip" &
done

# Wait for all background jobs to complete
wait

# Count results
for ip in $PRIVATE_IPS; do
    host_log="/tmp/prod_host_${ip//./_}.log"
    if [ -f "$host_log" ]; then
        if grep -q "✅ SUCCESS: Deployed appContainer" "$host_log"; then
            CONTAINER_RESTART_COUNT=$((CONTAINER_RESTART_COUNT + 1))
        elif grep -q "CRITICAL:.*unreachable" "$host_log"; then
            UNREACHABLE_HOSTS=$((UNREACHABLE_HOSTS + 1))
        elif grep -q "FAILED: Deployment failed" "$host_log"; then
            FAILED_DEPLOYMENTS=$((FAILED_DEPLOYMENTS + 1))
        fi
        cat "$host_log"
        rm -f "$host_log"
    fi
done

# =============================================
# FINAL VERIFICATION - PRODUCTION STANDARDS
# =============================================
echo "=== Performing final production verification ==="

RUNNING_CONTAINERS=0
HEALTHY_CONTAINERS=0

for ip in $PRIVATE_IPS; do
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 "$SSH_USER@$ip" \
        "sudo docker ps --filter 'name=appContainer' --filter 'status=running' --format 'table {{.Names}}' | grep -q appContainer" 2>/dev/null; then
        echo "✅ PRODUCTION VERIFIED: appContainer running on $ip"
        RUNNING_CONTAINERS=$((RUNNING_CONTAINERS + 1))
        log_message "INFO" "Production verification passed for $ip"
        
        # Additional health check
        if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 "$SSH_USER@$ip" \
            "sudo docker inspect --format='{{.State.Status}}' appContainer | grep -q running" 2>/dev/null; then
            HEALTHY_CONTAINERS=$((HEALTHY_CONTAINERS + 1))
        fi
    else
        echo "❌ PRODUCTION ISSUE: appContainer NOT running on $ip"
        log_message "ERROR" "Production verification failed for $ip - container not running"
    fi
done

# =============================================
# PRODUCTION SUMMARY REPORT
# =============================================
echo ""
echo "=== PRODUCTION DEPLOYMENT SUMMARY ==="
echo "======================================"
echo "Auto Scaling Group: $ASG_NAME"
echo "Region: $REGION"
echo "Total instances discovered: $INSTANCE_COUNT"
echo "Instances with running containers: $RUNNING_CONTAINERS"
echo "Healthy containers: $HEALTHY_CONTAINERS"
echo "Containers restarted: $CONTAINER_RESTART_COUNT"
echo "Unreachable hosts: $UNREACHABLE_HOSTS"
echo "Failed deployments: $FAILED_DEPLOYMENTS"
echo "Ansible inventory: $INVENTORY_FILE"
echo "IP list: $IP_LIST_FILE"
echo "Log file: $LOG_FILE"
echo "======================================"

# Log summary
log_message "SUMMARY" "Production deployment completed - Instances: $INSTANCE_COUNT, Running: $RUNNING_CONTAINERS, Restarted: $CONTAINER_RESTART_COUNT, Unreachable: $UNREACHABLE_HOSTS, Failed: $FAILED_DEPLOYMENTS"

# Production health assessment
if [ $RUNNING_CONTAINERS -eq $INSTANCE_COUNT ] && [ $HEALTHY_CONTAINERS -eq $INSTANCE_COUNT ]; then
    echo "🎉 PRODUCTION SUCCESS: All instances have healthy appContainer running!"
    log_message "SUCCESS" "All production instances are healthy and running containers"
    exit 0
elif [ $RUNNING_CONTAINERS -eq 0 ]; then
    echo "💥 PRODUCTION CRITICAL: No instances have appContainer running!"
    log_message "CRITICAL" "No production instances have running containers"
    exit 1
elif [ $RUNNING_CONTAINERS -lt $INSTANCE_COUNT ]; then
    echo "⚠️  PRODUCTION WARNING: Only $RUNNING_CONTAINERS out of $INSTANCE_COUNT instances have appContainer running"
    log_message "WARNING" "Partial production deployment - $RUNNING_CONTAINERS/$INSTANCE_COUNT instances running"
    exit 2
else
    echo "❓ PRODUCTION UNKNOWN: Unexpected state"
    log_message "ERROR" "Unexpected production state"
    exit 3
fi