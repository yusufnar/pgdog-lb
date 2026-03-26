#!/bin/bash

# Test Artificial Lag Script
# Pauses WAL replay on pg-replica1 to simulate replication lag

REPLICA="pg-replica1"
PAUSE_DURATION=${1:-20}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          ARTIFICIAL LAG TEST - $REPLICA                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check current lag before pause
echo "[$(date +%H:%M:%S)] Current replication lag on $REPLICA:"
docker exec $REPLICA psql -U postgres -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp(), CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) * 1000 END as lag_ms;" 2>/dev/null

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

sleep 1

# Show PgDog status after lag created
echo ""
echo "[$(date +%H:%M:%S)] PgDog pool status (after 5s lag):"
PGPASSWORD=admin psql -h 127.0.0.1 -p 6432 -U admin -d pgdog -c "SHOW POOLS" 2>/dev/null

echo ""
echo "[$(date +%H:%M:%S)] Load balancing test (lagging replica should be banned if it exceeds threshold):"
echo "  Note: PgDog detects replication lag via ban_replica_lag setting."
for i in {1..5}; do
    ip=$(PGPASSWORD=secret psql -h 127.0.0.1 -p 6432 -U postgres -d appdb -t -c "SELECT inet_server_addr();" 2>/dev/null | tr -d '[:space:]')
    echo "    Query $i: $ip"
done

# Check lag during pause
echo ""
echo "[$(date +%H:%M:%S)] Current lag status on $REPLICA:"
docker exec $REPLICA psql -U postgres -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) * 1000 END as lag_ms;" 2>/dev/null

# Wait remaining time and continuously monitor lag
remaining=$((PAUSE_DURATION))
echo ""
echo "[$(date +%H:%M:%S)] Monitoring lag for ${remaining}s before resuming..."
for (( i=1; i<=remaining; i++ )); do
    lag_sec=$(docker exec $REPLICA psql -U postgres -t -c "SELECT CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) END;" 2>/dev/null | tr -d '[:space:]')
    echo "[$(date +%H:%M:%S)] [$i/$remaining] Replication Lag: ${lag_sec:-N/A}sec"
    sleep 1
done

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
echo "[$(date +%H:%M:%S)] Final replication lag on $REPLICA:"
docker exec $REPLICA psql -U postgres -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) * 1000 END as lag_ms;" 2>/dev/null

echo ""
echo "[$(date +%H:%M:%S)] Final PgDog pool status:"
PGPASSWORD=admin psql -h 127.0.0.1 -p 6432 -U admin -d pgdog -c "SHOW POOLS" 2>/dev/null

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          TEST COMPLETE                                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
