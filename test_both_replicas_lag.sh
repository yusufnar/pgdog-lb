#!/bin/bash

# Test Artificial Lag on BOTH Replicas
# Pauses WAL replay on both pg-replica1 and pg-replica2

PAUSE_DURATION=${1:-20}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║    ARTIFICIAL LAG TEST - BOTH REPLICAS                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check current lag before pause
echo "[$(date +%H:%M:%S)] Current replication lag:"
echo "pg-replica1:"
docker exec pg-replica1 psql -U postgres -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) * 1000 END as lag_ms;" 2>/dev/null
echo "pg-replica2:"
docker exec pg-replica2 psql -U postgres -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) * 1000 END as lag_ms;" 2>/dev/null

echo ""
echo "[$(date +%H:%M:%S)] Pausing WAL replay on BOTH replicas..."
docker exec pg-replica1 psql -U postgres -c "SELECT pg_wal_replay_pause();" 2>/dev/null
docker exec pg-replica2 psql -U postgres -c "SELECT pg_wal_replay_pause();" 2>/dev/null

# Check if paused
paused1=$(docker exec pg-replica1 psql -U postgres -t -c "SELECT pg_is_wal_replay_paused();" 2>/dev/null | tr -d '[:space:]')
paused2=$(docker exec pg-replica2 psql -U postgres -t -c "SELECT pg_is_wal_replay_paused();" 2>/dev/null | tr -d '[:space:]')

echo "[$(date +%H:%M:%S)] pg-replica1 paused: $paused1"
echo "[$(date +%H:%M:%S)] pg-replica2 paused: $paused2"

# Generate some writes to create lag
echo ""
echo "[$(date +%H:%M:%S)] Generating writes on primary to create lag..."
docker exec pg-primary psql -U postgres -d appdb -c "INSERT INTO ynar (info) VALUES ('both_lag_test');" >/dev/null 2>&1
echo "  Inserted row"

# Show PgDog status after lag created
echo ""
echo "[$(date +%H:%M:%S)] PgDog pool status (after lag on both):"
PGPASSWORD=admin psql -h 127.0.0.1 -p 6432 -U admin -d pgdog -c "SHOW POOLS" 2>/dev/null

echo ""
echo "[$(date +%H:%M:%S)] Load balancing test (both replicas lagging):"
echo "  Note: PgDog does NOT detect replication lag. Lagging replicas remain in the pool."
for i in {1..5}; do
    ip=$(PGPASSWORD=secret psql -h 127.0.0.1 -p 6432 -U postgres -d appdb -t -c "SELECT inet_server_addr();" 2>/dev/null | tr -d '[:space:]')
    echo "    Query $i: $ip"
done

# Check lag during pause
echo ""
echo "[$(date +%H:%M:%S)] Current lag status (both replicas paused):"
echo "pg-replica1:"
docker exec pg-replica1 psql -U postgres -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) END as lag_sec;" 2>/dev/null
echo "pg-replica2:"
docker exec pg-replica2 psql -U postgres -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) END as lag_sec;" 2>/dev/null

# Wait remaining time
remaining=$((PAUSE_DURATION - 5))
echo ""
echo "[$(date +%H:%M:%S)] Monitoring lag for ${remaining}s before resuming..."
for (( i=1; i<=remaining; i++ )); do
    lag1=$(docker exec pg-replica1 psql -U postgres -t -c "SELECT CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) END;" 2>/dev/null | tr -d '[:space:]')
    lag2=$(docker exec pg-replica2 psql -U postgres -t -c "SELECT CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) END;" 2>/dev/null | tr -d '[:space:]')
    echo "[$(date +%H:%M:%S)] [$i/$remaining] pg-replica1: ${lag1:-N/A}sec | pg-replica2: ${lag2:-N/A}sec"
    sleep 1
done

# Resume WAL replay on both
echo ""
echo "[$(date +%H:%M:%S)] Resuming WAL replay on BOTH replicas..."
docker exec pg-replica1 psql -U postgres -c "SELECT pg_wal_replay_resume();" 2>/dev/null
docker exec pg-replica2 psql -U postgres -c "SELECT pg_wal_replay_resume();" 2>/dev/null

# Check if resumed
paused1=$(docker exec pg-replica1 psql -U postgres -t -c "SELECT pg_is_wal_replay_paused();" 2>/dev/null | tr -d '[:space:]')
paused2=$(docker exec pg-replica2 psql -U postgres -t -c "SELECT pg_is_wal_replay_paused();" 2>/dev/null | tr -d '[:space:]')
echo "[$(date +%H:%M:%S)] pg-replica1 resumed: $([ "$paused1" = "f" ] && echo "✓" || echo "✗")"
echo "[$(date +%H:%M:%S)] pg-replica2 resumed: $([ "$paused2" = "f" ] && echo "✓" || echo "✗")"

# Wait for lag to clear
echo ""
echo "[$(date +%H:%M:%S)] Waiting for lag to clear..."
sleep 3

# Final status
echo ""
echo "[$(date +%H:%M:%S)] Final replication lag:"
echo "pg-replica1:"
docker exec pg-replica1 psql -U postgres -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) * 1000 END as lag_ms;" 2>/dev/null
echo "pg-replica2:"
docker exec pg-replica2 psql -U postgres -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) * 1000 END as lag_ms;" 2>/dev/null

echo ""
echo "[$(date +%H:%M:%S)] Final PgDog pool status:"
PGPASSWORD=admin psql -h 127.0.0.1 -p 6432 -U admin -d pgdog -c "SHOW POOLS" 2>/dev/null

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          TEST COMPLETE                                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
