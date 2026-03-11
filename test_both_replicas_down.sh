#!/bin/bash

# Test Both Replicas Down Scenario
# Stops both pg-replica1 and pg-replica2 to test PgDog behavior

DOWN_DURATION=10

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║    BOTH REPLICAS DOWN TEST                                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Initial status
echo "[$(date +%H:%M:%S)] Initial PgDog pool status:"
PGPASSWORD=admin psql -h 127.0.0.1 -p 6432 -U admin -d pgdog -c "SHOW POOLS" 2>/dev/null

echo ""
echo "[$(date +%H:%M:%S)] Initial replication status:"
docker exec pg-primary psql -U postgres -c "SELECT client_addr, state, replay_lag FROM pg_stat_replication;" 2>/dev/null

# Stop both replicas
echo ""
echo "[$(date +%H:%M:%S)] ⛔ STOPPING pg-replica1..."
docker stop pg-replica1 >/dev/null 2>&1
echo "[$(date +%H:%M:%S)] ⛔ STOPPING pg-replica2..."
docker stop pg-replica2 >/dev/null 2>&1
echo "[$(date +%H:%M:%S)] Both replicas stopped."

# Wait for PgDog to detect
echo ""
echo "[$(date +%H:%M:%S)] Waiting 5s for PgDog to detect..."
sleep 5

# Show status after stop
echo ""
echo "[$(date +%H:%M:%S)] PgDog pool status (both replicas stopped):"
PGPASSWORD=admin psql -h 127.0.0.1 -p 6432 -U admin -d pgdog -c "SHOW POOLS" 2>/dev/null

echo ""
echo "[$(date +%H:%M:%S)] Replication status (both replicas stopped):"
docker exec pg-primary psql -U postgres -c "SELECT client_addr, state, replay_lag FROM pg_stat_replication;" 2>/dev/null

# Test if queries still work (should fail or go to primary if primary_reads_enabled)
echo ""
echo "[$(date +%H:%M:%S)] Testing queries (all replicas down, primary_reads_enabled=false):"
echo "  Note: Queries may fail if PgDog can't route to any replica."
for i in 1 2 3 4 5; do
    ip=$(PGPASSWORD=secret psql -h 127.0.0.1 -p 6432 -U postgres -d appdb -t -c "SELECT inet_server_addr();" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$ip" ]; then
        echo "  Query $i: $ip"
    else
        echo "  Query $i: FAILED (no available replica)"
    fi
done

# Wait remaining time
remaining=$((DOWN_DURATION - 5))
echo ""
echo "[$(date +%H:%M:%S)] Waiting ${remaining}s before restarting..."
sleep $remaining

# Start both replicas again
echo ""
echo "[$(date +%H:%M:%S)] ▶️  STARTING pg-replica1..."
docker start pg-replica1 >/dev/null 2>&1
echo "[$(date +%H:%M:%S)] ▶️  STARTING pg-replica2..."
docker start pg-replica2 >/dev/null 2>&1
echo "[$(date +%H:%M:%S)] Both replicas started."

# Wait for recovery
echo ""
echo "[$(date +%H:%M:%S)] Waiting 15s for replicas to recover and sync..."
sleep 15

# Final status
echo ""
echo "[$(date +%H:%M:%S)] Final PgDog pool status:"
PGPASSWORD=admin psql -h 127.0.0.1 -p 6432 -U admin -d pgdog -c "SHOW POOLS" 2>/dev/null

echo ""
echo "[$(date +%H:%M:%S)] Final replication status:"
docker exec pg-primary psql -U postgres -c "SELECT client_addr, state, replay_lag FROM pg_stat_replication;" 2>/dev/null

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          TEST COMPLETE                                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
