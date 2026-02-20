#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

backup_postgres() {
    local backup_dir="/var/backups/postgresql"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${backup_dir}/postgres_backup_${timestamp}.sql.gz"
    
    log_info "Creating PostgreSQL backup..."
    
    ssh root@db-primary "mkdir -p $backup_dir"
    
    ssh root@db-primary "sudo -u postgres pg_dumpall | gzip > $backup_file"
    
    local size=$(ssh root@db-primary "ls -lh $backup_file | awk '{print \$5}'")
    log_success "PostgreSQL backup created: $backup_file ($size)"
    
    log_info "Copying backup to local machine..."
    mkdir -p ./backups
    scp root@db-primary:$backup_file ./backups/
    
    log_success "Backup copied locally: ./backups/postgres_backup_${timestamp}.sql.gz"
    
    log_info "Cleaning old backups (keeping last 7)..."
    ssh root@db-primary "ls -t ${backup_dir}/postgres_backup_*.sql.gz | tail -n +8 | xargs -r rm"
}

backup_redis() {
    local backup_dir="/var/backups/redis"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    log_info "Creating Redis backup..."
    
    ssh root@redis-1 "mkdir -p $backup_dir"
    ssh root@redis-1 "redis-cli BGSAVE"
    
    sleep 5
    
    ssh root@redis-1 "cp /var/lib/redis/dump.rdb ${backup_dir}/redis_backup_${timestamp}.rdb"
    
    log_success "Redis backup created: ${backup_dir}/redis_backup_${timestamp}.rdb"
    
    mkdir -p ./backups
    scp root@redis-1:${backup_dir}/redis_backup_${timestamp}.rdb ./backups/
    
    log_success "Backup copied locally"
}

backup_configs() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="configs_${timestamp}.tar.gz"
    
    log_info "Backing up configurations..."
    
    mkdir -p ./backups/tmp
    
    for host in lb-1 lb-2 lb-3; do
        mkdir -p ./backups/tmp/$host
        scp root@$host:/etc/nginx/nginx.conf ./backups/tmp/$host/ 2>/dev/null || true
        scp root@$host:/etc/keepalived/keepalived.conf ./backups/tmp/$host/ 2>/dev/null || true
    done
    
    for host in db-primary db-replica; do
        mkdir -p ./backups/tmp/$host
        scp root@$host:/etc/postgresql/*/main/postgresql.conf ./backups/tmp/$host/ 2>/dev/null || true
        scp root@$host:/etc/postgresql/*/main/pg_hba.conf ./backups/tmp/$host/ 2>/dev/null || true
    done
    
    tar -czf ./backups/$backup_file -C ./backups/tmp .
    rm -rf ./backups/tmp
    
    log_success "Configuration backup created: ./backups/$backup_file"
}

rotate_backups() {
    local retention_days=${1:-30}
    
    log_info "Rotating backups older than $retention_days days..."
    
    find ./backups -type f -mtime +$retention_days -delete
    
    log_success "Backup rotation complete"
}

show_usage() {
    echo "Usage: $0 {postgres|redis|configs|all|rotate [days]}"
    echo ""
    echo "Commands:"
    echo "  postgres    - Backup PostgreSQL database"
    echo "  redis       - Backup Redis data"
    echo "  configs     - Backup configuration files"
    echo "  all         - Backup everything"
    echo "  rotate [N]  - Remove backups older than N days (default: 30)"
}

case "${1:-}" in
    postgres)
        backup_postgres
        ;;
    redis)
        backup_redis
        ;;
    configs)
        backup_configs
        ;;
    all)
        backup_postgres
        backup_redis
        backup_configs
        ;;
    rotate)
        rotate_backups "${2:-30}"
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
