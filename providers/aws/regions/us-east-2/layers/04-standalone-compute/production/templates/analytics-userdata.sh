#!/bin/bash
# =============================================================================
# Analytics Instance Setup Script
# =============================================================================
# This script sets up an analytics instance for client-specific workloads
# with Python, Jupyter, and data analysis tools.
# =============================================================================

set -euo pipefail

# Configuration variables from Terraform
CLIENT_NAME="${CLIENT_NAME}"
REGION="${REGION}"
ENVIRONMENT="${ENVIRONMENT}"
VPC_CIDR="${VPC_CIDR}"

# Logging setup
LOG_FILE="/var/log/analytics-setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting analytics instance setup for client: $CLIENT_NAME"

# =============================================================================
# System Update and Basic Packages
# =============================================================================
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Updating system packages"

yum update -y
yum install -y \
    htop \
    tree \
    wget \
    curl \
    unzip \
    git \
    vim \
    tmux \
    awscli \
    jq

# =============================================================================
# Mount Additional EBS Volume
# =============================================================================
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Configuring additional EBS volume"

# Wait for the device to be available
while [ ! -e /dev/xvdf ]; do
    echo "Waiting for /dev/xvdf to be available..."
    sleep 5
done

# Create filesystem if not exists
if ! blkid /dev/xvdf; then
    echo "Creating filesystem on /dev/xvdf"
    mkfs.ext4 /dev/xvdf
fi

# Create mount point and mount
mkdir -p /opt/analytics-data
mount /dev/xvdf /opt/analytics-data

# Add to fstab for persistent mounting
echo "/dev/xvdf /opt/analytics-data ext4 defaults,noatime 0 2" >> /etc/fstab

# Set appropriate permissions
chown ec2-user:ec2-user /opt/analytics-data
chmod 755 /opt/analytics-data

# =============================================================================
# Install Python and Analytics Stack
# =============================================================================
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing Python and analytics tools"

# Install Python 3.9 and pip
amazon-linux-extras install python3.8 -y
yum install -y python3-devel python3-pip

# Create analytics environment
su - ec2-user -c "
    # Create workspace directories
    mkdir -p /opt/analytics-data/workspaces
    mkdir -p /opt/analytics-data/datasets
    mkdir -p /opt/analytics-data/models
    mkdir -p /opt/analytics-data/notebooks
    
    # Create virtual environment
    python3 -m venv /opt/analytics-data/venv
    source /opt/analytics-data/venv/bin/activate
    
    # Install analytics packages
    pip install --upgrade pip
    pip install \
        jupyter \
        jupyterlab \
        pandas \
        numpy \
        matplotlib \
        seaborn \
        scikit-learn \
        plotly \
        boto3 \
        psycopg2-binary \
        sqlalchemy \
        requests \
        flask \
        fastapi \
        uvicorn
"

# =============================================================================
# Configure Jupyter Lab
# =============================================================================
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Configuring Jupyter Lab"

su - ec2-user -c "
    source /opt/analytics-data/venv/bin/activate
    
    # Generate Jupyter configuration
    jupyter lab --generate-config
    
    # Configure Jupyter to listen on all interfaces
    cat >> /home/ec2-user/.jupyter/jupyter_lab_config.py << EOF
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.token = ''
c.ServerApp.password = ''
c.ServerApp.allow_origin = '*'
c.ServerApp.allow_remote_access = True
c.ServerApp.root_dir = '/opt/analytics-data/notebooks'
EOF
"

# =============================================================================
# Create Systemd Services
# =============================================================================
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating systemd services"

# Jupyter Lab service
cat > /etc/systemd/system/jupyter-lab.service << EOF
[Unit]
Description=Jupyter Lab for $CLIENT_NAME
After=network.target

[Service]
Type=simple
User=ec2-user
Environment=PATH=/opt/analytics-data/venv/bin:/usr/local/bin:/usr/bin:/bin
WorkingDirectory=/opt/analytics-data/notebooks
ExecStart=/opt/analytics-data/venv/bin/jupyter lab
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
systemctl daemon-reload
systemctl enable jupyter-lab
systemctl start jupyter-lab

# =============================================================================
# Install CloudWatch Agent
# =============================================================================
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing CloudWatch agent"

# Download and install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm
rm -f ./amazon-cloudwatch-agent.rpm

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "Analytics/${ENVIRONMENT}/${CLIENT_NAME}",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60,
                "resources": ["*"],
                "totalcpu": false
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "diskio": {
                "measurement": ["io_time"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/analytics-setup.log",
                        "log_group_name": "/aws/ec2/analytics/${CLIENT_NAME}",
                        "log_stream_name": "{instance_id}/setup"
                    },
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "/aws/ec2/analytics/${CLIENT_NAME}",
                        "log_stream_name": "{instance_id}/messages"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# =============================================================================
# Create Sample Notebooks and Configuration
# =============================================================================
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating sample notebooks and configuration"

su - ec2-user -c "
    # Create sample notebook for client
    cat > /opt/analytics-data/notebooks/welcome-${CLIENT_NAME}.ipynb << 'EOF'
{
 \"cells\": [
  {
   \"cell_type\": \"markdown\",
   \"metadata\": {},
   \"source\": [
    \"# Analytics Workspace for ${CLIENT_NAME}\\n\",
    \"\\n\",
    \"Welcome to your dedicated analytics environment!\\n\",
    \"\\n\",
    \"## Available Tools\\n\",
    \"- Python 3.8 with scientific computing stack\\n\",
    \"- Pandas, NumPy, Matplotlib, Seaborn\\n\",
    \"- Scikit-learn for machine learning\\n\",
    \"- Plotly for interactive visualizations\\n\",
    \"- PostgreSQL connectivity (psycopg2)\\n\",
    \"- AWS SDK (boto3)\\n\",
    \"\\n\",
    \"## Data Directories\\n\",
    \"- \\\`/opt/analytics-data/datasets\\\`: Raw data files\\n\",
    \"- \\\`/opt/analytics-data/models\\\`: Trained models\\n\",
    \"- \\\`/opt/analytics-data/workspaces\\\`: Project workspaces\"
   ]
  },
  {
   \"cell_type\": \"code\",
   \"execution_count\": null,
   \"metadata\": {},
   \"outputs\": [],
   \"source\": [
    \"# Quick environment check\\n\",
    \"import pandas as pd\\n\",
    \"import numpy as np\\n\",
    \"import matplotlib.pyplot as plt\\n\",
    \"import seaborn as sns\\n\",
    \"import boto3\\n\",
    \"\\n\",
    \"print('Analytics environment ready!')\\n\",
    \"print(f'Client: ${CLIENT_NAME}')\\n\",
    \"print(f'Region: ${REGION}')\\n\",
    \"print(f'Environment: ${ENVIRONMENT}')\"
   ]
  }
 ],
 \"metadata\": {
  \"kernelspec\": {
   \"display_name\": \"Python 3\",
   \"language\": \"python\",
   \"name\": \"python3\"
  },
  \"language_info\": {
   \"name\": \"python\",
   \"version\": \"3.8.0\"
  }
 },
 \"nbformat\": 4,
 \"nbformat_minor\": 4
}
EOF

    # Create client-specific configuration file
    cat > /opt/analytics-data/.client-config << EOF
CLIENT_NAME=${CLIENT_NAME}
REGION=${REGION}
ENVIRONMENT=${ENVIRONMENT}
VPC_CIDR=${VPC_CIDR}

# Database connection template (update with actual credentials)
DB_HOST=<database-ip>
DB_PORT=5432
DB_NAME=<database-name>
DB_USER=<database-user>
DB_PASSWORD=<database-password>

# Data directories
DATASETS_DIR=/opt/analytics-data/datasets
MODELS_DIR=/opt/analytics-data/models
WORKSPACES_DIR=/opt/analytics-data/workspaces
NOTEBOOKS_DIR=/opt/analytics-data/notebooks
EOF
"

# =============================================================================
# Final Setup and Permissions
# =============================================================================
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Finalizing setup"

# Ensure all permissions are correct
chown -R ec2-user:ec2-user /opt/analytics-data
find /opt/analytics-data -type d -exec chmod 755 {} \;
find /opt/analytics-data -type f -exec chmod 644 {} \;

# Make scripts executable
find /opt/analytics-data -name "*.sh" -exec chmod +x {} \;

# Create completion marker
su - ec2-user -c "touch /opt/analytics-data/.setup-complete"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Analytics instance setup completed successfully!"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Jupyter Lab is available at: http://\$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4):8888"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Access restricted to client subnet: ${VPC_CIDR}"

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack ${CLIENT_NAME}-analytics --resource AnalyticsInstance --region ${REGION} || true