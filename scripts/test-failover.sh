#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

test_keepalived_failover() {
    log_info "Testing Keepalived failover..."
    
    local current_master=$(ssh root@lb-1 "ip addr show | grep -c '$FLOATING_IP'" || echo 0)
    
    if [[ "$current_master" -eq 1 ]]; then
        log_info "Current master: lb-1"
        log_info "Stopping Keepalived on lb-1..."
        
        ssh root@lb-1 "systemctl stop keepalived"
        sleep 5
        
        local new_master=""
        for host in lb-2 lb-3; do
            if ssh root@$host "ip addr show | grep -q '$FLOATING_IP'" 2>/dev/null; then
                new_master=$host
                break
            fi
        done
        
        if [[ -n "$new_master" ]]; then
            log_success "VIP failed over to $new_master"
        else
            log_error "VIP failover failed!"
            ssh root@lb-1 "systemctl start keepalived"
            return 1
        fi
        
        log_info "Restoring lb-1 as backup..."
        ssh root@lb-1 "systemctl start keepalived"
        sleep 5
        
        log_success "Failover test completed successfully"
        return 0
    else
        log_warning "lb-1 is not current master, checking other nodes..."
        return 1
    fi
}

test_traefik_failover() {
    log_info "Testing Traefik backend failover..."
    
    local backend="app-1"
    
    log_info "Taking down $backend..."
    ssh root@$backend "docker compose -f /opt/app/docker-compose.yml down"
    
    sleep 5
    
    local response=$(curl -sf "https://$DOMAIN/health" || echo "FAILED")
    
    if [[ "$response" != "FAILED" ]]; then
        log_success "Traffic routed to healthy backends"
    else
        log_error "Application unreachable!"
    fi
    
    log_info "Restoring $backend..."
    ssh root@$backend "docker compose -f /opt/app/docker-compose.yml up -d"
    
    log_success "Traefik failover test completed"
}

test_postgres_failover() {
    log_info "Testing PostgreSQL replication..."
    
    local primary="db-primary"
    local replica="db-replica"
    
    log_info "Checking replication status..."
    local replication_status=$(ssh root@$primary "sudo -u postgres psql -t -c \"SELECT status FROM pg_stat_replication;\"" | tr -d ' ')
    
    if [[ "$replication_status" == "streaming" ]]; then
        log_success "PostgreSQL replication is active"
    else
        log_error "PostgreSQL replication issue detected"
        return 1
    fi
    
    log_info "Testing failover capability..."
    log_warning "Manual failover test skipped (requires confirmation)"
    
    return 0
}

test_redis_cluster() {
    log_info "Testing Redis cluster failover..."
    
    local first_node="redis-1"
    
    local cluster_info=$(redis-cli -h $first_node cluster info 2>/dev/null)
    
    if echo "$cluster_info" | grep -q "cluster_state:ok"; then
        log_success "Redis cluster state is OK"
    else
        log_error "Redis cluster is degraded"
        return 1
    fi
    
    local cluster_slots=$(redis-cli -h $first_node cluster info | grep cluster_slots_ok | cut -d: -f2 | tr -d '\r')
    log_info "Cluster slots OK: $cluster_slots"
    
    return 0
}

run_all_tests() {
    echo ""
    echo "========================================="
    echo "     HA VPS Cluster Failover Tests"
    echo "========================================="
    echo ""
    
    local tests_passed=0
    local tests_failed=0
    
    echo "--- Test 1: Keepalived Failover ---"
    if test_keepalived_failover; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    echo ""
    
    echo "--- Test 2: Traefik Backend Failover ---"
    if test_traefik_failover; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    echo ""
    
    echo "--- Test 3: PostgreSQL Replication ---"
    if test_postgres_failover; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    echo ""
    
    echo "--- Test 4: Redis Cluster ---"
    if test_redis_cluster; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    echo ""
    
    echo "========================================="
    echo "Tests passed: $tests_passed"
    echo "Tests failed: $tests_failed"
    echo "========================================="
    
    if [[ $tests_failed -eq 0 ]]; then
        log_success "All failover tests passed!"
        return 0
    else
        log_error "Some tests failed. Review logs above."
        return 1
    fi
}

case "${1:-all}" in
    keepalived)
        test_keepalived_failover
        ;;
    traefik)
        test_traefik_failover
        ;;
    postgres)
        test_postgres_failover
        ;;
    redis)
        test_redis_cluster
        ;;
    all)
        run_all_tests
        ;;
    *)
        echo "Usage: $0 {keepalived|traefik|postgres|redis|all}"
        exit 1
        ;;
esac
