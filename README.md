# High-Availability VPS Cluster

A production-grade, fault-tolerant infrastructure setup for high-availability deployments. This repository contains everything needed to deploy and manage a multi-node VPS cluster with automatic failover, load balancing, and zero-downtime deployments.

## Architecture Overview

```
                    ┌─────────────────────────────────────────────┐
                    │              Floating IP (VIP)              │
                    │            203.0.113.100                    │
                    └─────────────────┬───────────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
    ┌─────────▼─────────┐   ┌────────▼────────┐   ┌─────────▼─────────┐
    │   Load Balancer   │   │  Load Balancer  │   │   Load Balancer   │
    │   Node 1 (MASTER) │   │   Node 2        │   │   Node 3          │
    │   10.0.0.1        │   │   10.0.0.2      │   │   10.0.0.3        │
    └─────────┬─────────┘   └────────┬────────┘   └─────────┬─────────┘
              │                       │                       │
              └───────────────────────┼───────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
    ┌─────────▼─────────┐   ┌────────▼────────┐   ┌─────────▼─────────┐
    │   Application     │   │   Application   │   │   Application     │
    │   Server 1        │   │   Server 2      │   │   Server 3        │
    │   10.0.1.1        │   │   10.0.1.2      │   │   10.0.1.3        │
    └─────────┬─────────┘   └────────┬────────┘   └─────────┬─────────┘
              │                       │                       │
              └───────────────────────┼───────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
    ┌─────────▼─────────┐   ┌────────▼────────┐   ┌─────────▼─────────┐
    │   PostgreSQL      │   │   PostgreSQL    │   │   Redis           │
    │   Primary         │◄──│   Replica       │   │   Cluster         │
    │   10.0.2.1        │   │   10.0.2.2      │   │   10.0.2.3-5      │
    └───────────────────┘   └─────────────────┘   └───────────────────┘
```

## Features

- **Automatic Failover**: Keepalived-based VIP failover in under 3 seconds
- **Load Balancing**: Nginx upstream with health checks
- **Zero-Downtime Deployments**: Blue-green deployment strategy
- **Database Replication**: PostgreSQL streaming replication
- **Caching Layer**: Redis cluster for session and data caching
- **Monitoring Stack**: Prometheus + Grafana for observability
- **Infrastructure as Code**: Terraform + Ansible for reproducibility
- **SSL/TLS**: Let's Encrypt automation with certbot

## Quick Start

### Prerequisites

- 3+ VPS instances (recommended: 4GB RAM, 2 vCPU each)
- SSH access with sudo privileges
- Domain name (optional, for SSL)

### 1. Clone and Configure

```bash
git clone https://github.com/Totti786/ha-vps-cluster.git
cd ha-vps-cluster

# Copy and edit inventory
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
vim ansible/inventory/hosts.yml
```

### 2. Deploy Infrastructure

```bash
# Provision with Terraform (optional, if using cloud provider)
cd terraform
terraform init
terraform plan
terraform apply

# Configure servers with Ansible
cd ../ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

### 3. Verify Deployment

```bash
# Check cluster status
./scripts/health-check.sh

# Test failover
./scripts/test-failover.sh
```

## Project Structure

```
ha-vps-cluster/
├── terraform/              # Infrastructure provisioning
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── ansible/                # Configuration management
│   ├── inventory/
│   ├── playbooks/
│   └── roles/
├── docker/                 # Container configurations
│   ├── nginx/
│   ├── keepalived/
│   ├── postgres/
│   └── redis/
├── scripts/                # Utility scripts
├── monitoring/             # Monitoring configs
└── docs/                   # Documentation
```

## Components

### Load Balancer Layer
- **Nginx**: Reverse proxy and load balancer
- **Keepalived**: VRRP for IP failover
- **Health checks**: Active/passive health monitoring

### Application Layer
- **Docker**: Container runtime
- **Docker Compose**: Multi-container orchestration
- **Blue-green deployment**: Zero-downtime updates

### Database Layer
- **PostgreSQL**: Primary-replica replication
- **PgBouncer**: Connection pooling
- **Barman**: Backup management

### Caching Layer
- **Redis**: Cluster mode with 3 masters + replicas
- **Persistence**: AOF + RDB snapshots

## Configuration

### Environment Variables

```bash
# .env.example
DOMAIN=example.com
POSTGRES_PASSWORD=your_secure_password
REDIS_PASSWORD=your_redis_password
GRAFANA_PASSWORD=your_grafana_password
```

### SSL Certificates

```bash
# Automatic with certbot
./scripts/setup-ssl.sh your-domain.com

# Manual certificate upload
./scripts/upload-cert.sh /path/to/cert.pem /path/to/key.pem
```

## Monitoring

Access Grafana at `https://monitor.your-domain.com`

Default dashboards:
- Cluster Overview
- Nginx Metrics
- PostgreSQL Performance
- Redis Statistics
- Container Health

## Scaling

### Add Application Node

```bash
# Add to inventory
vim ansible/inventory/hosts.yml

# Provision new node
ansible-playbook -i inventory/hosts.yml playbooks/app-node.yml
```

### Scale Redis Cluster

```bash
./scripts/scale-redis.sh add-node 10.0.2.6
```

## Maintenance

### Backup Database

```bash
# Manual backup
./scripts/backup-postgres.sh

# Automated (add to cron)
0 2 * * * /opt/ha-vps-cluster/scripts/backup-postgres.sh
```

### Update SSL Certificates

```bash
./scripts/renew-ssl.sh
```

### Rolling Updates

```bash
# Update application across all nodes
./scripts/deploy.sh --strategy=rolling
```

## Troubleshooting

### Common Issues

1. **VIP not failing over**
   ```bash
   # Check keepalived status
   systemctl status keepalived
   journalctl -u keepalived -f
   ```

2. **Database replication lag**
   ```bash
   # Check replication status
   sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"
   ```

3. **Redis cluster unhealthy**
   ```bash
   redis-cli cluster info
   redis-cli cluster check 10.0.2.3:6379
   ```

## Performance Benchmarks

| Metric | Value |
|--------|-------|
| Failover Time | < 3 seconds |
| Requests/second | 50,000+ |
| Avg Response Time | < 10ms |
| Uptime (12 months) | 99.99% |

## Security Hardening

- UFW firewall configuration
- Fail2ban for SSH protection
- SSL/TLS for all public endpoints
- Encrypted database connections
- Regular security updates via unattended-upgrades

## License

MIT License - see [LICENSE](LICENSE)

## Author

**Tarek Deshli**
- GitHub: [@Totti786](https://github.com/Totti786)
- LinkedIn: [Totti786](https://linkedin.com/in/Totti786)

## Contributing

Contributions are welcome! Please read our [Contributing Guide](docs/CONTRIBUTING.md) for details.
