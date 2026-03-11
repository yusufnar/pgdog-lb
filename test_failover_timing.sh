#!/bin/bash

echo "========================================================"
echo "FAILOVER TIMING TEST"
echo "========================================================"

# Log PostgreSQL instance IPs
echo ""
echo "[$(date +%H:%M:%S)] PostgreSQL Instance IPs:"
for container in pg-primary pg-replica1 pg-replica2; do
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $container 2>/dev/null)
    if [ -n "$IP" ]; then
        echo "    $container: $IP"
    else
        echo "    $container: (not running)"
    fi
done
echo ""

# Function to check if PgDog can reach pg-replica1
# Sends a query and checks if it reaches pg-replica1's IP
get_replica1_reachable() {
    local replica1_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' pg-replica1 2>/dev/null)
    for i in {1..5}; do
        local ip=$(PGPASSWORD=secret psql -h 127.0.0.1 -p 6432 -U postgres -d appdb -t -c "SELECT inet_server_addr();" 2>/dev/null | tr -d '[:space:]')
        if [ "$ip" = "$replica1_ip" ]; then
            echo "reachable"
            return
        fi
    done
    echo "not_reachable"
}

# Initial status
echo "[$(date +%H:%M:%S)] Initial Status:"
echo "--- PgDog Pool Status ---"
PGPASSWORD=admin psql -h 127.0.0.1 -p 6432 -U admin -d pgdog -c "SHOW POOLS" 2>/dev/null

echo ""
echo "[$(date +%H:%M:%S)] Testing load balancing (5 queries):"
for i in {1..5}; do
    ip=$(PGPASSWORD=secret psql -h 127.0.0.1 -p 6432 -U postgres -d appdb -t -c "SELECT inet_server_addr();" 2>/dev/null | tr -d '[:space:]')
    echo "    Query $i: $ip"
done

echo ""
echo "[$(date +%H:%M:%S)] STOPPING pg-replica1..."
STOP_TIME=$(date +%s)
docker stop pg-replica1 > /dev/null

# Poll for PgDog to detect failure (banned)
echo "[$(date +%H:%M:%S)] Waiting for PgDog to detect failure..."
while true; do
    STATUS=$(get_replica1_reachable)
    if [ "$STATUS" == "not_reachable" ]; then
        DOWN_TIME=$(date +%s)
        DETECT_DURATION=$((DOWN_TIME - STOP_TIME))
        echo "[$(date +%H:%M:%S)] ✅ PgDog no longer routing to pg-replica1"
        echo "    Detection time: ${DETECT_DURATION} seconds"
        break
    fi
    sleep 1
done

echo ""
echo "[$(date +%H:%M:%S)] STARTING pg-replica1..."
START_TIME=$(date +%s)
docker start pg-replica1 > /dev/null

# Poll for recovery
echo "[$(date +%H:%M:%S)] Waiting for PgDog to recover pg-replica1..."
while true; do
    STATUS=$(get_replica1_reachable)
    if [ "$STATUS" == "reachable" ]; then
        UP_TIME=$(date +%s)
        RECOVERY_DURATION=$((UP_TIME - START_TIME))
        echo "[$(date +%H:%M:%S)] ✅ PgDog routing to pg-replica1 again"
        echo "    Recovery time: ${RECOVERY_DURATION} seconds"
        break
    fi
    sleep 1
done

echo ""
echo "========================================================"
echo "SUMMARY"
echo "========================================================"
echo "Failure Detection Time: ${DETECT_DURATION} seconds"
echo "Auto-Recovery Time:     ${RECOVERY_DURATION} seconds"
echo "========================================================"

# Final status
echo ""
echo "[$(date +%H:%M:%S)] Final Status:"
./check_pgdog_nodes.sh | head -15
