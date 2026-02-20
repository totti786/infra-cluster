#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="${SCRIPT_DIR}/../ansible/inventory/hosts.yml"
FLOATING_IP="${FLOATING_IP:-203.0.113.100}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${2}${1}${NC}"
}

check_vip() {
    if ping -c 1 -W 2 "$FLOATING_IP" &>/dev/null; then
        print_status "✓ VIP ($FLOATING_IP) is reachable" "$GREEN"
        return 0
    else
        print_status "✗ VIP ($FLOATING_IP) is NOT reachable" "$RED"
        return 1
    fi
}

check_nginx() {
    local host=$1
    if curl -sf "http://$host/health" &>/dev/null; then
        print_status "✓ Nginx healthy on $host" "$GREEN"
        return 0
    else
        print_status "✗ Nginx NOT healthy on $host" "$RED"
        return 1
    fi
}

check_postgres() {
    local host=$1
    if pg_isready -h "$host" -p 5432 -U postgres &>/dev/null; then
        print_status "✓ PostgreSQL healthy on $host" "$GREEN"
        return 0
    else
        print_status "✗ PostgreSQL NOT healthy on $host" "$RED"
        return 1
    fi
}

check_redis() {
    local host=$1
    if redis-cli -h "$host" ping 2>/dev/null | grep -q PONG; then
        print_status "✓ Redis healthy on $host" "$GREEN"
        return 0
    else
        print_status "✗ Redis NOT healthy on $host" "$RED"
        return 1
    fi
}

check_redis_cluster() {
    local first_redis=$(grep -A1 "redis_cluster:" "$INVENTORY_FILE" | grep ansible_host | head -1 | awk '{print $2}')
    if redis-cli -h "$first_redis" cluster info 2>/dev/null | grep -q "cluster_state:ok"; then
        print_status "✓ Redis cluster state is OK" "$GREEN"
        return 0
    else
        print_status "✗ Redis cluster state is NOT OK" "$RED"
        return 1
    fi
}

check_keepalived() {
    local host=$1
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$host" "systemctl is-active keepalived" &>/dev/null; then
        local state=$(ssh "root@$host" "cat /etc/keepalived/keepalived.conf | grep -A1 'state' | tail -1 | awk '{print \$2}'")
        print_status "✓ Keepalived ($state) running on $host" "$GREEN"
        return 0
    else
        print_status "✗ Keepalived NOT running on $host" "$RED"
        return 1
    fi
}

check_replication() {
    local primary="db-primary"
    local replica="db-replica"
    
    local lag=$(ssh "root@$primary" "sudo -u postgres psql -t -c \"SELECT EXTRACT(EPOCH FROM (now() - replay_timestamp)) FROM pg_stat_replication;\"" 2>/dev/null | tr -d ' ')
    
    if [[ -n "$lag" ]] && (( $(echo "$lag < 10" | bc -l) )); then
        print_status "✓ PostgreSQL replication lag: ${lag}s" "$GREEN"
        return 0
    else
        print_status "✗ PostgreSQL replication lag high: ${lag}s" "$YELLOW"
        return 1
    fi
}

main() {
    echo "========================================="
    echo "     HA VPS Cluster Health Check"
    echo "========================================="
    echo ""
    
    local failures=0
    
    echo "--- Network & VIP ---"
    check_vip || ((failures++))
    echo ""
    
    echo "--- Load Balancers ---"
    for host in lb-1 lb-2 lb-3; do
        check_nginx "$host" || ((failures++))
        check_keepalived "$host" || ((failures++))
    done
    echo ""
    
    echo "--- Databases ---"
    check_postgres "db-primary" || ((failures++))
    check_postgres "db-replica" || ((failures++))
    check_replication || ((failures++))
    echo ""
    
    echo "--- Redis ---"
    for host in redis-1 redis-2 redis-3; do
        check_redis "$host" || ((failures++))
    done
    check_redis_cluster || ((failures++))
    echo ""
    
    echo "========================================="
    if [[ $failures -eq 0 ]]; then
        print_status "All checks passed! Cluster is healthy." "$GREEN"
        exit 0
    else
        print_status "$failures check(s) failed!" "$RED"
        exit 1
    fi
}

main "$@"
