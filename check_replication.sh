#!/bin/bash

# Function to print header
print_header() {
    echo "========================================================"
    echo "$1"
    echo "========================================================"
}

# 1. Check initial lag on Primary
print_header "1. Initial Replication Lag Check (on Primary)"
docker exec pg-primary psql -U postgres -c "
SELECT 
    client_addr, 
    application_name, 
    state, 
    sync_state, 
    replay_lag,
    COALESCE(replay_lag::text, 'NULL (idle)') as replay_lag_status
FROM pg_stat_replication;
"

# 1b. Check initial lag on Replicas
print_header "1b. Initial Replication Lag Check (from Replicas)"
for replica in pg-replica1 pg-replica2; do
    echo "Checking $replica..."
    docker exec $replica psql -U postgres -c "
    SELECT 
        pg_last_wal_replay_lsn() as replay_lsn,
        pg_last_xact_replay_timestamp() as last_replay_time,
        now() - pg_last_xact_replay_timestamp() as actual_time_lag,
        EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) as lag_seconds
    "
    echo ""
done

# 2. Insert new record to Primary
print_header "2. Inserting new record into Primary"
NEW_DATA="test_data_$(date +%s)"
echo "Inserting info: '$NEW_DATA'"
docker exec pg-primary psql -U postgres -d appdb -c "INSERT INTO ynar (info) VALUES ('$NEW_DATA');"

# 3. Check new record on Replicas
print_header "3. Verifying data on Replicas"
for replica in pg-replica1 pg-replica2; do
    echo "Checking $replica..."
    docker exec $replica psql -U postgres -d appdb -c "SELECT * FROM ynar ORDER BY id DESC LIMIT 1;"
done

# 4. Check Recovery Status
print_header "4. Checking pg_is_in_recovery() on Replicas"
for replica in pg-replica1 pg-replica2; do
    echo "Checking $replica..."
    STATUS=$(docker exec $replica psql -U postgres -t -c "SELECT pg_is_in_recovery();" | tr -d '[:space:]')
    echo "Is in recovery? $STATUS"
    if [ "$STATUS" == "t" ]; then
        echo "✅ Correct: Node is in recovery mode (Read-Only)."
    else
        echo "❌ ERROR: Node is NOT in recovery mode!"
    fi
done

# 5. Check lag again 1- FROM PRIMARY SIDE
print_header "5. Final Replication Lag Check (on Primary)"
docker exec pg-primary psql -U postgres -c "
SELECT 
    client_addr, 
    application_name, 
    state, 
    sync_state, 
    replay_lag,
    COALESCE(replay_lag::text, 'NULL (idle)') as replay_lag_status,
    pg_last_xact_replay_timestamp() as last_replay_time,
    now() - pg_last_xact_replay_timestamp() as actual_replay_delay
FROM pg_stat_replication;
"

# 6. Check lag again 2- FROM REPLICA SIDE (more accurate)
print_header "5. Final Replication Lag Check (from Replicas - More Accurate)"
for replica in pg-replica1 pg-replica2; do
    echo "Checking $replica..."
    docker exec $replica psql -U postgres -c "
    SELECT 
        pg_last_wal_replay_lsn() as replay_lsn,
        pg_last_xact_replay_timestamp() as last_replay_time,
        now() - pg_last_xact_replay_timestamp() as actual_time_lag,
        EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) as lag_seconds
    "
    echo ""
done


echo ""
echo "Script completed."
