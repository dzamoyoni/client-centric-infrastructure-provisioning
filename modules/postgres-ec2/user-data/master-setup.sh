#!/bin/bash
# ============================================================================
# PostgreSQL Master Database Setup Script
# ============================================================================
# This script sets up PostgreSQL master instance with:
# - PostgreSQL installation and configuration
# - Replication user setup
# - Custom database and user creation
# - Automated backups and monitoring
# - EBS volume mounting and configuration
# - Performance optimization
# ============================================================================

set -euo pipefail

# Configuration variables (populated by Terraform)
POSTGRES_VERSION="${postgres_version}"
POSTGRES_PORT="${postgres_port}"
REPLICA_USER="${replica_user}"
REPLICA_PASSWORD="${replica_password}"
DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
BACKUP_RETENTION="${backup_retention}"
MONITORING_ENABLED="${monitoring_enabled}"
CLIENT_NAME="${client_name}"

# System configuration
POSTGRES_USER="postgres"
DATA_DIR="/var/lib/postgresql/$POSTGRES_VERSION/main"
CONFIG_DIR="/etc/postgresql/$POSTGRES_VERSION/main"
LOG_FILE="/var/log/postgres-setup.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting PostgreSQL master setup for client: $CLIENT_NAME"

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

# Setup backup volume (/dev/sdh -> /var/backups/postgresql)
wait_for_device "/dev/sdh"
if ! blkid /dev/sdh; then
    log "Formatting backup volume"
    mkfs.ext4 -F /dev/sdh
fi

log "Mounting backup volume"
mkdir -p /var/backups/postgresql
mount /dev/sdh /var/backups/postgresql
echo '/dev/sdh /var/backups/postgresql ext4 defaults,nofail 0 2' >> /etc/fstab

# ============================================================================
# POSTGRESQL INSTALLATION
# ============================================================================

log "Installing PostgreSQL $POSTGRES_VERSION"

# Add PostgreSQL official APT repository
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/postgresql.list

apt-get update -y
apt-get install -y postgresql-$POSTGRES_VERSION postgresql-contrib-$POSTGRES_VERSION postgresql-client-$POSTGRES_VERSION

# Stop PostgreSQL to configure it
systemctl stop postgresql

# ============================================================================
# POSTGRESQL CONFIGURATION
# ============================================================================

log "Configuring PostgreSQL"

# Set up directory permissions
chown -R postgres:postgres /var/lib/postgresql
chown -R postgres:postgres /var/backups/postgresql
chmod 700 /var/lib/postgresql/$POSTGRES_VERSION
chmod 755 /var/lib/postgresql/wal
chmod 755 /var/backups/postgresql

# Initialize database if needed
if [ ! -f "$DATA_DIR/PG_VERSION" ]; then
    log "Initializing PostgreSQL database"
    sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/initdb -D "$DATA_DIR" --auth-local peer --auth-host md5
fi

# Configure PostgreSQL for replication and performance
log "Configuring postgresql.conf"
cat >> "$CONFIG_DIR/postgresql.conf" << EOF

# ============================================================================
# Client: $CLIENT_NAME - PostgreSQL Master Configuration
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

# WAL and replication settings
wal_level = replica
max_wal_senders = 3
max_replication_slots = 3
wal_keep_size = 1GB
wal_log_hints = on

# WAL archiving and backup
archive_mode = on
archive_command = 'cp %p /var/backups/postgresql/wal_archive/%f'
archive_timeout = 300

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

# Configure pg_hba.conf for replication
log "Configuring pg_hba.conf"
cat >> "$CONFIG_DIR/pg_hba.conf" << EOF

# Replication connections
host    replication     $REPLICA_USER    10.0.0.0/8             md5
host    replication     $REPLICA_USER    172.16.0.0/12          md5

# Application connections
host    $DB_NAME        $DB_USER         10.0.0.0/8             md5
host    $DB_NAME        $DB_USER         172.16.0.0/12          md5

EOF

# ============================================================================
# PREPARE WAL DIRECTORY AND ARCHIVES
# ============================================================================

log "Setting up WAL directory and archives"

# Create WAL directory symlink
sudo -u postgres mkdir -p /var/lib/postgresql/wal/pg_wal
if [ -d "$DATA_DIR/pg_wal" ] && [ ! -L "$DATA_DIR/pg_wal" ]; then
    # Move existing WAL files and create symlink
    sudo -u postgres mv "$DATA_DIR/pg_wal"/* /var/lib/postgresql/wal/pg_wal/ 2>/dev/null || true
    sudo -u postgres rmdir "$DATA_DIR/pg_wal"
    sudo -u postgres ln -sf /var/lib/postgresql/wal/pg_wal "$DATA_DIR/pg_wal"
elif [ ! -L "$DATA_DIR/pg_wal" ]; then
    sudo -u postgres ln -sf /var/lib/postgresql/wal/pg_wal "$DATA_DIR/pg_wal"
fi

# Create WAL archive directory
mkdir -p /var/backups/postgresql/wal_archive
chown postgres:postgres /var/backups/postgresql/wal_archive
chmod 750 /var/backups/postgresql/wal_archive

# ============================================================================
# START POSTGRESQL AND CREATE USERS/DATABASES
# ============================================================================

log "Starting PostgreSQL"
systemctl start postgresql
systemctl enable postgresql

# Wait for PostgreSQL to start
sleep 10

log "Creating replication user"
sudo -u postgres psql -c "CREATE USER $REPLICA_USER REPLICATION LOGIN ENCRYPTED PASSWORD '$REPLICA_PASSWORD';" || true

log "Creating application database and user"
sudo -u postgres createdb "$DB_NAME" || true
sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';" || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" || true
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO $DB_USER;" || true

# Create pg_stat_statements extension
sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;" || true

# ============================================================================
# BACKUP SETUP
# ============================================================================

log "Setting up automated backups"

# Create backup script
cat > /usr/local/bin/postgresql-backup.sh << EOF
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/var/backups/postgresql/dumps"
RETENTION_DAYS=${backup_retention}
DB_NAME="${db_name}"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)

mkdir -p "\$BACKUP_DIR"

# Full database backup
pg_dump -U postgres -d "\$DB_NAME" | gzip > "\$BACKUP_DIR/\$DB_NAME\_\$TIMESTAMP.sql.gz"

# Cleanup old backups
find "\$BACKUP_DIR" -name "*.sql.gz" -mtime +\$RETENTION_DAYS -delete

# Log backup completion
logger "PostgreSQL backup completed for \$DB_NAME"
EOF

chmod +x /usr/local/bin/postgresql-backup.sh

# Set up daily backup cron job
echo "0 2 * * * /usr/local/bin/postgresql-backup.sh" | crontab -u postgres -

# ============================================================================
# MONITORING SETUP
# ============================================================================

if [ "$MONITORING_ENABLED" = "true" ]; then
    log "Setting up PostgreSQL monitoring"
    
    # Install postgres_exporter for Prometheus
    EXPORTER_VERSION="0.15.0"
    wget -O /tmp/postgres_exporter.tar.gz "https://github.com/prometheus-community/postgres_exporter/releases/download/v$EXPORTER_VERSION/postgres_exporter-$EXPORTER_VERSION.linux-amd64.tar.gz"
    tar -xzf /tmp/postgres_exporter.tar.gz -C /tmp
    mv "/tmp/postgres_exporter-$EXPORTER_VERSION.linux-amd64/postgres_exporter" /usr/local/bin/
    
    # Create monitoring user
    sudo -u postgres psql -c "CREATE USER postgres_exporter WITH ENCRYPTED PASSWORD 'monitoring_password';" || true
    sudo -u postgres psql -c "GRANT CONNECT ON DATABASE $DB_NAME TO postgres_exporter;" || true
    sudo -u postgres psql -c "GRANT pg_monitor TO postgres_exporter;" || true
    
    # Create systemd service for postgres_exporter
    cat > /etc/systemd/system/postgres_exporter.service << EOF
[Unit]
Description=PostgreSQL Exporter
After=postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=postgres
Group=postgres
Environment=DATA_SOURCE_NAME=postgresql://postgres_exporter:monitoring_password@localhost:$POSTGRES_PORT/$DB_NAME?sslmode=disable
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
# HEALTH CHECK SETUP
# ============================================================================

log "Setting up health check"

cat > /usr/local/bin/postgres-health-check.sh << EOF
#!/bin/bash
set -euo pipefail

# Check if PostgreSQL is running
if ! systemctl is-active --quiet postgresql; then
    echo "CRITICAL: PostgreSQL is not running"
    exit 2
fi

# Check database connectivity
if ! sudo -u postgres psql -d $DB_NAME -c "SELECT 1;" > /dev/null 2>&1; then
    echo "CRITICAL: Cannot connect to database $DB_NAME"
    exit 2
fi

# Check replication status
if ! sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;" > /dev/null 2>&1; then
    echo "WARNING: Cannot query replication status"
    exit 1
fi

echo "OK: PostgreSQL master is healthy"
exit 0
EOF

chmod +x /usr/local/bin/postgres-health-check.sh

# Set up health check cron job
echo "*/5 * * * * /usr/local/bin/postgres-health-check.sh >> /var/log/postgres-health.log 2>&1" | crontab -u postgres -

# ============================================================================
# COMPLETION
# ============================================================================

log "PostgreSQL master setup completed successfully"
log "Database: $DB_NAME"
log "Port: $POSTGRES_PORT"
log "Replication user: $REPLICA_USER"
log "Data directory: $DATA_DIR"
log "WAL directory: /var/lib/postgresql/wal/pg_wal"
log "Backup directory: /var/backups/postgresql"

# Create status file
echo "$(date): PostgreSQL master setup completed for client $CLIENT_NAME" > /tmp/postgres-master-ready

log "Setup complete. PostgreSQL master is ready for replication."
