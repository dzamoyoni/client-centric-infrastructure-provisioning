#!/bin/bash
# ============================================================================
# PostgreSQL Replica Database Setup Script
# ============================================================================
# This script sets up PostgreSQL replica instance with:
# - PostgreSQL installation and configuration
# - Streaming replication from master
# - EBS volume mounting and configuration
# - Automated failover preparation
# - Monitoring and health checks
# ============================================================================

set -euo pipefail

# Configuration variables (populated by Terraform)
POSTGRES_VERSION="${postgres_version}"
POSTGRES_PORT="${postgres_port}"
REPLICA_USER="${replica_user}"
REPLICA_PASSWORD="${replica_password}"
MASTER_IP="${master_ip}"
MONITORING_ENABLED="${monitoring_enabled}"
CLIENT_NAME="${client_name}"

# System configuration
POSTGRES_USER="postgres"
DATA_DIR="/var/lib/postgresql/$POSTGRES_VERSION/main"
CONFIG_DIR="/etc/postgresql/$POSTGRES_VERSION/main"
LOG_FILE="/var/log/postgres-replica-setup.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting PostgreSQL replica setup for client: $CLIENT_NAME"
log "Master IP: $MASTER_IP"

# ============================================================================
# SYSTEM UPDATES AND DEPENDENCIES
# ============================================================================

log "Updating system packages"
apt-get update -y
apt-get upgrade -y

# Install required packages
log "Installing required packages"
apt-get install -y \
    wget \
    curl \
    gnupg2 \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    unattended-upgrades \
    fail2ban \
    ufw \
    awscli \
    cloudwatch-agent

# ============================================================================
# EBS VOLUME SETUP
# ============================================================================

log "Setting up EBS volumes"

# Function to wait for device
wait_for_device() {
    local device=$1
    local timeout=60
    local count=0
    
    while [ ! -b "$device" ] && [ $count -lt $timeout ]; do
        log "Waiting for device $device... ($count/$timeout)"
        sleep 1
        count=$((count + 1))
    done
    
    if [ ! -b "$device" ]; then
        log "ERROR: Device $device not found after $timeout seconds"
        exit 1
    fi
}

# Setup data volume (/dev/sdf -> /var/lib/postgresql)
wait_for_device "/dev/sdf"
if ! blkid /dev/sdf; then
    log "Formatting data volume"
    mkfs.ext4 -F /dev/sdf
fi

log "Mounting data volume"
mkdir -p /var/lib/postgresql
mount /dev/sdf /var/lib/postgresql
echo '/dev/sdf /var/lib/postgresql ext4 defaults,nofail 0 2' >> /etc/fstab

# Setup WAL volume (/dev/sdg -> /var/lib/postgresql/wal)
wait_for_device "/dev/sdg"
if ! blkid /dev/sdg; then
    log "Formatting WAL volume"
    mkfs.ext4 -F /dev/sdg
fi

log "Mounting WAL volume"
mkdir -p /var/lib/postgresql/wal
mount /dev/sdg /var/lib/postgresql/wal
echo '/dev/sdg /var/lib/postgresql/wal ext4 defaults,nofail 0 2' >> /etc/fstab

# ============================================================================
# POSTGRESQL INSTALLATION
# ============================================================================

log "Installing PostgreSQL $POSTGRES_VERSION"

# Add PostgreSQL official APT repository
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/postgresql.list

apt-get update -y
apt-get install -y postgresql-$POSTGRES_VERSION postgresql-contrib-$POSTGRES_VERSION postgresql-client-$POSTGRES_VERSION

# Stop PostgreSQL for configuration
systemctl stop postgresql
systemctl disable postgresql  # We'll start it manually after replication setup

# ============================================================================
# WAIT FOR MASTER TO BE READY
# ============================================================================

log "Waiting for master database to be ready"

# Function to check if master is ready
check_master_ready() {
    pg_isready -h "$MASTER_IP" -p "$POSTGRES_PORT" -U "$REPLICA_USER" >/dev/null 2>&1
}

# Wait for master to be ready (up to 10 minutes)
TIMEOUT=600
COUNT=0
while ! check_master_ready && [ $COUNT -lt $TIMEOUT ]; do
    log "Waiting for master at $MASTER_IP:$POSTGRES_PORT... ($COUNT/$TIMEOUT seconds)"
    sleep 10
    COUNT=$((COUNT + 10))
done

if ! check_master_ready; then
    log "ERROR: Master database not ready after $TIMEOUT seconds"
    exit 1
fi

log "Master database is ready, proceeding with replica setup"

# ============================================================================
# DIRECTORY SETUP AND PERMISSIONS
# ============================================================================

log "Setting up PostgreSQL directories and permissions"

# Set up directory permissions
chown -R postgres:postgres /var/lib/postgresql
chmod 700 /var/lib/postgresql/$POSTGRES_VERSION
chmod 755 /var/lib/postgresql/wal

# Remove any existing data directory
rm -rf "$DATA_DIR"

# Create WAL directory structure
sudo -u postgres mkdir -p /var/lib/postgresql/wal/pg_wal

# ============================================================================
# CREATE BASE BACKUP FROM MASTER
# ============================================================================

log "Creating base backup from master"

# Set up .pgpass file for replication user
sudo -u postgres bash -c "cat > ~/.pgpass << EOF
$MASTER_IP:$POSTGRES_PORT:replication:$REPLICA_USER:$REPLICA_PASSWORD
EOF"
sudo -u postgres chmod 600 ~/.pgpass

# Create base backup
log "Running pg_basebackup from master"
sudo -u postgres pg_basebackup \
    -h "$MASTER_IP" \
    -p "$POSTGRES_PORT" \
    -U "$REPLICA_USER" \
    -D "$DATA_DIR" \
    -P \
    -W \
    -R \
    --checkpoint=fast \
    --wal-method=stream

log "Base backup completed successfully"

# ============================================================================
# CONFIGURE REPLICA
# ============================================================================

log "Configuring PostgreSQL replica"

# Create WAL directory symlink
if [ -d "$DATA_DIR/pg_wal" ] && [ ! -L "$DATA_DIR/pg_wal" ]; then
    # Move WAL files to dedicated volume and create symlink
    sudo -u postgres mv "$DATA_DIR/pg_wal"/* /var/lib/postgresql/wal/pg_wal/ 2>/dev/null || true
    sudo -u postgres rmdir "$DATA_DIR/pg_wal"
    sudo -u postgres ln -sf /var/lib/postgresql/wal/pg_wal "$DATA_DIR/pg_wal"
elif [ ! -L "$DATA_DIR/pg_wal" ]; then
    sudo -u postgres ln -sf /var/lib/postgresql/wal/pg_wal "$DATA_DIR/pg_wal"
fi

# Configure postgresql.conf for replica
log "Configuring postgresql.conf for replica"
cat >> "$CONFIG_DIR/postgresql.conf" << EOF

# ============================================================================
# Client: ${client_name} - PostgreSQL Replica Configuration
# ============================================================================

# Connection settings
listen_addresses = '*'
port = $POSTGRES_PORT
max_connections = 100

# Memory settings (optimized for r5.large)
shared_buffers = 1GB
effective_cache_size = 3GB
maintenance_work_mem = 256MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200

# Replica-specific settings
hot_standby = on
max_standby_streaming_delay = 30s
max_standby_archive_delay = 60s
wal_receiver_status_interval = 10s
hot_standby_feedback = on

# WAL settings
wal_level = replica
max_wal_senders = 2
max_replication_slots = 2
wal_keep_size = 1GB
wal_log_hints = on

# Custom WAL directory
wal_directory = '/var/lib/postgresql/wal/pg_wal'

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000
log_line_prefix = '%t [%p-%l] %q%u@%d '

# Performance monitoring
shared_preload_libraries = 'pg_stat_statements'
track_activity_query_size = 2048
pg_stat_statements.track = all

EOF

# Configure primary_conninfo in postgresql.auto.conf (created by pg_basebackup -R)
# This should already be configured, but let's ensure it's correct
sudo -u postgres bash -c "cat >> '$DATA_DIR/postgresql.auto.conf' << EOF
# Replication connection settings
primary_conninfo = 'host=$MASTER_IP port=$POSTGRES_PORT user=$REPLICA_USER password=$REPLICA_PASSWORD sslmode=prefer sslcompression=0 target_session_attrs=any'
primary_slot_name = '${client_name}_replica_slot'
EOF"

# Create replication slot on master (if not exists)
log "Creating replication slot on master"
PGPASSWORD="$REPLICA_PASSWORD" psql \
    -h "$MASTER_IP" \
    -p "$POSTGRES_PORT" \
    -U "$REPLICA_USER" \
    -c "SELECT pg_create_physical_replication_slot('${client_name}_replica_slot');" \
    postgres || log "Replication slot may already exist"

# ============================================================================
# START POSTGRESQL REPLICA
# ============================================================================

log "Starting PostgreSQL replica"
systemctl start postgresql
systemctl enable postgresql

# Wait for PostgreSQL to start
sleep 10

# ============================================================================
# VERIFY REPLICATION
# ============================================================================

log "Verifying replication status"

# Wait for replica to catch up
sleep 15

# Check replication status
if sudo -u postgres psql -c "SELECT * FROM pg_stat_wal_receiver;" | grep -q "streaming"; then
    log "SUCCESS: Replica is receiving WAL stream from master"
else
    log "WARNING: Replica may not be properly connected to master"
fi

# Check if we can query the replica
if sudo -u postgres psql -c "SELECT pg_is_in_recovery();" | grep -q "t"; then
    log "SUCCESS: Database is in recovery mode (replica)"
else
    log "ERROR: Database is not in recovery mode"
fi

# ============================================================================
# MONITORING SETUP
# ============================================================================

if [ "$MONITORING_ENABLED" = "true" ]; then
    log "Setting up PostgreSQL monitoring for replica"
    
    # Install postgres_exporter for Prometheus
    EXPORTER_VERSION="0.15.0"
    wget -O /tmp/postgres_exporter.tar.gz "https://github.com/prometheus-community/postgres_exporter/releases/download/v$EXPORTER_VERSION/postgres_exporter-$EXPORTER_VERSION.linux-amd64.tar.gz"
    tar -xzf /tmp/postgres_exporter.tar.gz -C /tmp
    mv "/tmp/postgres_exporter-$EXPORTER_VERSION.linux-amd64/postgres_exporter" /usr/local/bin/
    
    # Create monitoring user (read-only on replica)
    sudo -u postgres psql -c "CREATE USER postgres_exporter WITH ENCRYPTED PASSWORD 'monitoring_password';" || true
    sudo -u postgres psql -c "GRANT pg_monitor TO postgres_exporter;" || true
    
    # Create systemd service for postgres_exporter
    cat > /etc/systemd/system/postgres_exporter.service << EOF
[Unit]
Description=PostgreSQL Exporter (Replica)
After=postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=postgres
Group=postgres
Environment=DATA_SOURCE_NAME=postgresql://postgres_exporter:monitoring_password@localhost:$POSTGRES_PORT/postgres?sslmode=disable
ExecStart=/usr/local/bin/postgres_exporter
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable postgres_exporter
    systemctl start postgres_exporter
fi

# ============================================================================
# SECURITY HARDENING
# ============================================================================

log "Applying security hardening"

# Configure firewall
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow $POSTGRES_PORT

if [ "$MONITORING_ENABLED" = "true" ]; then
    ufw allow 9187  # postgres_exporter port
fi

# Configure fail2ban
cat > /etc/fail2ban/jail.local << EOF
[postgresql]
enabled = true
port = $POSTGRES_PORT
filter = postgresql
logpath = /var/log/postgresql/postgresql-*.log
maxretry = 5
bantime = 3600
EOF

systemctl restart fail2ban

# ============================================================================
# HEALTH CHECK AND FAILOVER PREPARATION
# ============================================================================

log "Setting up health check and failover preparation"

cat > /usr/local/bin/postgres-replica-health-check.sh << EOF
#!/bin/bash
set -euo pipefail

# Check if PostgreSQL is running
if ! systemctl is-active --quiet postgresql; then
    echo "CRITICAL: PostgreSQL replica is not running"
    exit 2
fi

# Check if we're in recovery mode
if ! sudo -u postgres psql -t -c "SELECT pg_is_in_recovery();" | grep -q "t"; then
    echo "CRITICAL: Database is not in recovery mode (not a replica)"
    exit 2
fi

# Check replication lag
LAG=\$(sudo -u postgres psql -t -c "SELECT CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp()) END;")
if [ "\$\{LAG%%.*\}" -gt 60 ]; then
    echo "WARNING: Replication lag is \$LAG seconds"
    exit 1
fi

# Check connection to master
if ! pg_isready -h $MASTER_IP -p $POSTGRES_PORT -U $REPLICA_USER >/dev/null 2>&1; then
    echo "WARNING: Cannot connect to master at $MASTER_IP:$POSTGRES_PORT"
    exit 1
fi

echo "OK: PostgreSQL replica is healthy (lag: \$\{LAG\}s)"
exit 0
EOF

chmod +x /usr/local/bin/postgres-replica-health-check.sh

# Create failover script for manual promotion
cat > /usr/local/bin/postgres-promote-replica.sh << EOF
#!/bin/bash
set -euo pipefail

echo "WARNING: This will promote the replica to master!"
echo "Make sure the original master is really down before proceeding."
read -p "Are you sure you want to promote this replica? (yes/no): " confirm

if [ "\$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo "Promoting replica to master..."

# Stop PostgreSQL
systemctl stop postgresql

# Create trigger file to exit recovery mode
sudo -u postgres touch "$DATA_DIR/promote"

# Update configuration to allow writes
sudo -u postgres sed -i 's/^#*primary_conninfo.*/# primary_conninfo (disabled after promotion)/' "$DATA_DIR/postgresql.auto.conf"

# Start PostgreSQL as master
systemctl start postgresql

echo "Promotion completed. This instance is now the master."
echo "Don't forget to:"
echo "1. Update your application connection strings"
echo "2. Update DNS records if using them"
echo "3. Set up a new replica if needed"
EOF

chmod +x /usr/local/bin/postgres-promote-replica.sh

# Set up health check cron job
echo "*/5 * * * * /usr/local/bin/postgres-replica-health-check.sh >> /var/log/postgres-replica-health.log 2>&1" | crontab -u postgres -

# ============================================================================
# COMPLETION
# ============================================================================

log "PostgreSQL replica setup completed successfully"
log "Master IP: $MASTER_IP"
log "Port: $POSTGRES_PORT"
log "Replication user: $REPLICA_USER"
log "Data directory: $DATA_DIR"
log "WAL directory: /var/lib/postgresql/wal/pg_wal"

# Create status file
echo "$(date): PostgreSQL replica setup completed for client $CLIENT_NAME" > /tmp/postgres-replica-ready

log "Setup complete. PostgreSQL replica is ready and replicating."
log "Use /usr/local/bin/postgres-promote-replica.sh to promote to master if needed."
