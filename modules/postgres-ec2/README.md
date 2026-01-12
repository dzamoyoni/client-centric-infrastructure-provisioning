# PostgreSQL on EC2 Module

This Terraform module deploys highly available PostgreSQL databases on EC2 instances with master-replica replication setup, designed for client-specific isolation and enterprise-grade reliability.

## Features

### **High Availability Architecture**
- **Master-Replica Setup**: Automatic streaming replication between master and replica instances
- **Cross-AZ Deployment**: Master and replica in different availability zones for fault tolerance
- **Automated Failover Preparation**: Scripts ready for manual or automated promotion
- **Data Persistence**: Separate EBS volumes for data, WAL, and backups

### **Security & Isolation**
- **Client-Specific Security Groups**: Isolated network access per client
- **Encrypted Storage**: EBS encryption with optional KMS keys
- **Firewall Configuration**: UFW with fail2ban protection
- **SSH Access Control**: Configurable management access
- **PostgreSQL Authentication**: MD5 password authentication with restricted access

### **Monitoring & Observability**
- **PostgreSQL Exporter**: Prometheus metrics for master and replica
- **Health Checks**: Automated monitoring of replication status and database health
- **Performance Monitoring**: pg_stat_statements enabled for query analysis
- **Logging**: Structured PostgreSQL logs with rotation
- **CloudWatch Integration**: Optional CloudWatch agent setup

### **Storage Architecture**
- **Optimized EBS Volumes**: Separate volumes for data, WAL, and backups
- **Performance Tuned**: GP3 volumes with configurable IOPS and throughput
- **Backup Strategy**: Automated daily backups with configurable retention
- **WAL Archiving**: Continuous WAL archiving for point-in-time recovery

## Usage

### Basic Example

```hcl
module "client_database" {
  source = "../modules/postgres-ec2"
  
  # Client identification
  client_name = "client"
  environment = "production"
  
  # Network configuration
  vpc_id            = "vpc-0123456789abcdef0"
  master_subnet_id  = "subnet-0123456789abcdef0"  # us-east-1a
  replica_subnet_id = "subnet-0987654321fedcba0"  # us-east-1b
  
  # Instance configuration
  ami_id = "ami-0c7217cdde317cfec"  # Ubuntu 22.04 LTS
  key_name = "my-keypair"
  
  # Database configuration
  database_name     = "db_app_1"
  database_user     = "db_app_1_user"
  database_password = "secure_password_123"
  replication_password = "repl_password_456"
  
  # Network access
  allowed_cidr_blocks     = ["10.0.0.0/16", "172.16.0.0/12"]
  management_cidr_blocks  = ["10.0.1.0/24"]
  
  tags = {
    Owner       = "client-team"
    CostCenter  = "client-production"
    Environment = "production"
  }
}
```

### Advanced Configuration

```hcl
module "high_performance_database" {
  source = "../modules/postgres-ec2"
  
  # Client identification
  client_name = "client_name"
  environment = "production"
  
  # Network configuration
  vpc_id            = data.aws_vpc.main.id
  master_subnet_id  = data.aws_subnet.private_1a.id
  replica_subnet_id = data.aws_subnet.private_1b.id
  
  # High-performance instances
  master_instance_type  = "r5.xlarge"
  replica_instance_type = "r5.large"
  
  # Instance configuration
  ami_id   = data.aws_ami.ubuntu.id
  key_name = var.ec2_key_name
  
  # Database configuration
  postgres_version = "15"
  postgres_port    = 5432
  database_name    = "client_name_core"
  database_user    = "client_name_user"
  database_password = var.db_password
  replication_user     = "client_replicator"
  replication_password = var.repl_password
  
  # High-performance storage
  data_volume_size       = 500  # GB
  data_volume_type       = "gp3"
  data_volume_iops       = 10000
  data_volume_throughput = 500
  
  wal_volume_size        = 100  # GB
  wal_volume_type        = "gp3"
  wal_volume_iops        = 5000
  wal_volume_throughput  = 250
  
  backup_volume_size = 200  # GB
  
  # Security
  enable_encryption        = true
  kms_key_id              = aws_kms_key.database.arn
  enable_deletion_protection = true
  
  # Network access
  allowed_cidr_blocks    = ["172.16.0.0/12"]
  management_cidr_blocks = ["172.16.1.0/24"]
  monitoring_cidr_blocks = ["172.16.2.0/24"]
  
  # Monitoring and backup
  enable_monitoring       = true
  backup_retention_days   = 14
  
  # DNS (optional)
  create_dns_records = true
  private_zone_id   = aws_route53_zone.internal.zone_id
  domain_name       = "internal.company.com"
  
  tags = {
    Owner        = "client_name-database-team"
    CostCenter   = "client_name-production"
    BusinessUnit = "telecommunications"
    Backup       = "daily"
    Monitoring   = "enabled"
  }
}
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    PostgreSQL HA Architecture                  │
└─────────────────────────────────────────────────────────────────┘

    VPC: 172.16.0.0/16
    ┌─────────────────────────────────────────────────────────────┐
    │                                                             │
    │  AZ-1a (Master)              AZ-1b (Replica)               │
    │  ┌─────────────────┐         ┌─────────────────┐           │
    │  │   PostgreSQL    │◄────────┤   PostgreSQL    │           │
    │  │     Master      │  WAL    │     Replica     │           │
    │  │                 │ Stream  │                 │           │
    │  │  ┌─────────────┐│         │ ┌─────────────┐ │           │
    │  │  │ Data Volume ││         │ │ Data Volume │ │           │
    │  │  │   (GP3)     ││         │ │   (GP3)     │ │           │
    │  │  └─────────────┘│         │ └─────────────┘ │           │
    │  │  ┌─────────────┐│         │ ┌─────────────┐ │           │
    │  │  │ WAL Volume  ││         │ │ WAL Volume  │ │           │
    │  │  │   (GP3)     ││         │ │   (GP3)     │ │           │
    │  │  └─────────────┘│         │ └─────────────┘ │           │
    │  │  ┌─────────────┐│         │                 │           │
    │  │  │Backup Volume││         │                 │           │
    │  │  │   (GP3)     ││         │                 │           │
    │  │  └─────────────┘│         │                 │           │
    │  └─────────────────┘         └─────────────────┘           │
    │                                                             │
    └─────────────────────────────────────────────────────────────┘

    Applications connect to:
    - Master: Read/Write operations
    - Replica: Read-only operations (load balancing)
```

## Storage Layout

Each PostgreSQL instance uses optimized EBS volume configuration:

```
EC2 Instance
├── Root Volume (/): System and PostgreSQL binaries
│   └── Type: gp3, Size: 20GB (configurable)
│
├── Data Volume (/var/lib/postgresql): PostgreSQL data directory
│   ├── Type: gp3 (configurable: gp3, io1, io2)
│   ├── Size: 100GB (configurable)
│   ├── IOPS: 3000 (configurable)
│   └── Encrypted: Yes
│
├── WAL Volume (/var/lib/postgresql/wal): Write-Ahead Logs
│   ├── Type: gp3 (configurable)
│   ├── Size: 20GB (configurable)
│   ├── IOPS: 3000 (configurable)
│   └── Encrypted: Yes
│
└── Backup Volume (/var/backups/postgresql): Local backups
    ├── Type: gp3
    ├── Size: 50GB (configurable)
    └── Encrypted: Yes
```

## Replication Configuration

The module implements PostgreSQL streaming replication:

### Master Configuration
- **WAL Level**: `replica` - enables replication
- **Max WAL Senders**: `3` - supports multiple replicas
- **WAL Keep Size**: `1GB` - retains WAL for replica recovery
- **Archive Mode**: `on` - continuous WAL archiving
- **Replication Slots**: Physical slots for guaranteed WAL retention

### Replica Configuration
- **Hot Standby**: `on` - allows read-only queries
- **WAL Receiver**: Active streaming from master
- **Replication Lag Monitoring**: Built-in health checks
- **Automatic Recovery**: Base backup restoration on initialization

## Security Features

### Network Security
- **Dedicated Security Group**: Client-specific access rules
- **PostgreSQL Port**: Restricted to application subnets
- **SSH Access**: Optional, restricted to management subnets
- **Monitoring Port**: 9187 for PostgreSQL exporter (optional)

### Authentication & Authorization
- **Database Users**: Separate application and replication users
- **Password Authentication**: MD5 encrypted passwords
- **Connection Encryption**: SSL/TLS support ready
- **Host-Based Authentication**: IP-based access control

### Storage Security
- **EBS Encryption**: All volumes encrypted at rest
- **KMS Integration**: Custom KMS keys supported
- **Backup Encryption**: Encrypted backup storage
- **Volume Deletion Protection**: Configurable protection

## Monitoring & Health Checks

### Built-in Monitoring
- **PostgreSQL Exporter**: Prometheus metrics on port 9187
- **Health Check Scripts**: Master and replica health validation
- **Replication Lag Monitoring**: Real-time lag detection
- **Automated Alerting**: Cron-based health check logging

### Key Metrics
- Database connections and activity
- Query performance statistics
- Replication lag and status
- Storage utilization
- System resource usage

### Log Management
- **Structured Logging**: JSON format logs
- **Log Rotation**: Daily rotation with size limits
- **Query Logging**: Slow query logging enabled
- **Error Tracking**: Connection and replication errors

## Backup Strategy

### Automated Backups
- **Daily Full Backups**: pg_dump-based logical backups
- **WAL Archiving**: Continuous WAL file archiving
- **Retention Policy**: Configurable backup retention
- **Backup Verification**: Automated backup validation

### Point-in-Time Recovery
- **WAL Replay**: Complete transaction log preservation
- **Base Backup**: Full database state snapshots
- **Recovery Scripts**: Automated recovery procedures
- **Cross-AZ Backups**: Backup storage in dedicated volume

## Failover & Disaster Recovery

### Manual Failover
```bash
# On replica instance
sudo /usr/local/bin/postgres-promote-replica.sh
```

### Automated Failover (Future Enhancement)
- **Health Check Integration**: Consul or AWS health checks
- **DNS Failover**: Route 53 health-based routing
- **Application Awareness**: Connection string management

## Variables

### Required Variables

| Name | Type | Description |
|------|------|-------------|
| `client_name` | string | Client identifier for resource naming |
| `environment` | string | Environment (production, staging, etc.) |
| `vpc_id` | string | VPC ID for deployment |
| `master_subnet_id` | string | Subnet ID for master instance |
| `ami_id` | string | AMI ID for instances |
| `key_name` | string | EC2 key pair name |
| `database_name` | string | PostgreSQL database name |
| `database_user` | string | Application database user |
| `database_password` | string | Application user password |
| `replication_password` | string | Replication user password |

### Optional Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `replica_subnet_id` | string | `""` | Subnet ID for replica (different AZ recommended) |
| `enable_replica` | bool | `true` | Enable replica instance |
| `master_instance_type` | string | `"r5.large"` | Master instance type |
| `replica_instance_type` | string | `"r5.large"` | Replica instance type |
| `postgres_version` | string | `"15"` | PostgreSQL version |
| `postgres_port` | number | `5432` | PostgreSQL port |
| `data_volume_size` | number | `100` | Data volume size (GB) |
| `data_volume_type` | string | `"gp3"` | Data volume type |
| `enable_encryption` | bool | `true` | Enable EBS encryption |
| `enable_monitoring` | bool | `true` | Enable monitoring stack |
| `backup_retention_days` | number | `7` | Backup retention period |

## Outputs

### Connection Information
- `master_endpoint` - Master database connection endpoint
- `replica_endpoint` - Replica database connection endpoint  
- `database_port` - PostgreSQL port
- `database_name` - Database name

### Instance Information
- `master_instance_id` - Master EC2 instance ID
- `replica_instance_id` - Replica EC2 instance ID
- `master_private_ip` - Master private IP address
- `replica_private_ip` - Replica private IP address

### High Availability Status
- `high_availability_enabled` - Replica status
- `replication_status` - Detailed replication information

## Best Practices

### Instance Sizing
- **Memory**: PostgreSQL benefits from RAM (shared_buffers = 25% of RAM)
- **CPU**: Multi-core instances for concurrent connections
- **Storage**: Separate volumes for data, WAL, and backups
- **Network**: Enhanced networking for replication throughput

### Security Hardening
- **Regular Updates**: Automated security updates enabled
- **Access Control**: Principle of least privilege
- **Network Isolation**: VPC and security group restrictions
- **Monitoring**: Continuous security monitoring

### Performance Optimization
- **Connection Pooling**: Use pgBouncer or similar
- **Query Optimization**: Regular EXPLAIN ANALYZE
- **Index Management**: Monitor and maintain indexes
- **Statistics Updates**: Regular ANALYZE operations

### Operational Procedures
- **Regular Backups**: Test backup restoration procedures
- **Monitoring**: Set up alerts for key metrics
- **Maintenance**: Schedule regular maintenance windows
- **Documentation**: Maintain runbooks and procedures

## Troubleshooting

### Common Issues

**Replication Lag**
```bash
# Check replication status
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

# Check replica lag
sudo -u postgres psql -c "SELECT now() - pg_last_xact_replay_timestamp() AS lag;"
```

**Connection Issues**
```bash
# Test connectivity
pg_isready -h <host> -p 5432 -U <user>

# Check PostgreSQL logs
tail -f /var/log/postgresql/postgresql-*.log
```

**Storage Issues**
```bash
# Check disk usage
df -h /var/lib/postgresql

# Check EBS volume status
lsblk
```

## License

This module is provided under the MIT License. See LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review PostgreSQL documentation
3. Create an issue in the repository
4. Contact the database team
