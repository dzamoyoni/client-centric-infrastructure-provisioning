# Layer 03: Database Layer Outputs - Per-Client Architecture

output "client_databases" {
  description = "Per-client database configuration"
  value = {
    for client in keys(local.enabled_clients) : client => {
      master_instance_id  = module.client_postgres[client].master_instance_id
      master_private_ip   = module.client_postgres[client].master_private_ip
      master_endpoint     = module.client_postgres[client].master_endpoint
      replica_instance_id = module.client_postgres[client].replica_instance_id
      replica_private_ip  = module.client_postgres[client].replica_private_ip
      database_port       = module.client_postgres[client].database_port
      database_name       = module.client_postgres[client].database_name
      security_group_id   = module.client_postgres[client].security_group_id
      vpc_id              = local.client_database_config[client].vpc_id
    }
  }
  sensitive = true
}

output "database_summary" {
  description = "Database layer summary"
  value = {
    total_clients       = length(local.enabled_clients)
    architecture        = "Per-Client Complete Isolation"
    database_engine     = "PostgreSQL on EC2"
    high_availability   = "Master-Replica per client"
    network_isolation   = "Client-specific VPCs and subnets"
  }
}

output "client_database_endpoints" {
  description = "Database connection endpoints per client"
  value = {
    for client in keys(local.enabled_clients) : client => {
      master  = module.client_postgres[client].master_endpoint
      replica = module.client_postgres[client].replica_endpoint
      port    = module.client_postgres[client].database_port
    }
  }
  sensitive = true
}
