#!/bin/bash

# Test Artificial Lag Script
# Pauses WAL replay on pg-replica1 to simulate replication lag

REPLICA="pg-replica1"
PAUSE_DURATION=20

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          ARTIFICIAL LAG TEST - $REPLICA                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check current lag before pause
echo "[$(date +%H:%M:%S)] Current replication status:"
docker exec pg-primary psql -U postgres -c "SELECT client_addr, state, replay_lag FROM pg_stat_replication;" 2>/dev/null

echo ""
echo "[$(date +%H:%M:%S)] Pausing WAL replay on $REPLICA..."
docker exec $REPLICA psql -U postgres -c "SELECT pg_wal_replay_pause();" 2>/dev/null

# Check if paused
is_paused=$(docker exec $REPLICA psql -U postgres -t -c "SELECT pg_is_wal_replay_paused();" 2>/dev/null | tr -d '[:space:]')
if [ "$is_paused" = "t" ]; then
    echo "[$(date +%H:%M:%S)] ✓ WAL replay PAUSED on $REPLICA"
else
    echo "[$(date +%H:%M:%S)] ✗ Failed to pause WAL replay"
    exit 1
fi

# Generate some writes to create lag
echo ""
echo "[$(date +%H:%M:%S)] Generating writes on primary to create lag..."
docker exec pg-primary psql -U postgres -d appdb -c "INSERT INTO ynar (info) VALUES ('lag_test');" >/dev/null 2>&1
echo "  Inserted row"

sleep 5

# Show PgDog status after lag created
echo ""
echo "[$(date +%H:%M:%S)] PgDog pool status (after 5s lag):"
PGPASSWORD=admin psql -h 127.0.0.1 -p 6432 -U admin -d pgdog -c "SHOW POOLS" 2>/dev/null

echo ""
echo "[$(date +%H:%M:%S)] Load balancing test (both replicas should still receive queries):"
echo "  Note: PgDog does NOT detect replication lag. Lagging replicas remain in the pool."
for i in {1..5}; do
    ip=$(PGPASSWORD=secret psql -h 127.0.0.1 -p 6432 -U postgres -d appdb -t -c "SELECT inet_server_addr();" 2>/dev/null | tr -d '[:space:]')
    echo "    Query $i: $ip"
done

# Check lag during pause
echo ""
echo "[$(date +%H:%M:%S)] Current lag status (replica is paused):"
docker exec pg-primary psql -U postgres -c "SELECT client_addr, state, replay_lag FROM pg_stat_replication;" 2>/dev/null

# Wait remaining time
remaining=$((PAUSE_DURATION - 5))
echo ""
echo "[$(date +%H:%M:%S)] Waiting ${remaining}s before resuming..."
sleep $remaining

# Resume WAL replay
echo ""
echo "[$(date +%H:%M:%S)] Resuming WAL replay on $REPLICA..."
docker exec $REPLICA psql -U postgres -c "SELECT pg_wal_replay_resume();" 2>/dev/null

# Check if resumed
is_paused=$(docker exec $REPLICA psql -U postgres -t -c "SELECT pg_is_wal_replay_paused();" 2>/dev/null | tr -d '[:space:]')
if [ "$is_paused" = "f" ]; then
    echo "[$(date +%H:%M:%S)] ✓ WAL replay RESUMED on $REPLICA"
else
    echo "[$(date +%H:%M:%S)] ✗ Failed to resume WAL replay"
fi

# Wait for lag to clear
echo ""
echo "[$(date +%H:%M:%S)] Waiting for lag to clear..."
sleep 3

# Final status
echo ""
echo "[$(date +%H:%M:%S)] Final replication status:"
docker exec pg-primary psql -U postgres -c "SELECT client_addr, state, replay_lag FROM pg_stat_replication;" 2>/dev/null

echo ""
echo "[$(date +%H:%M:%S)] Final PgDog pool status:"
PGPASSWORD=admin psql -h 127.0.0.1 -p 6432 -U admin -d pgdog -c "SHOW POOLS" 2>/dev/null

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          TEST COMPLETE                                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
