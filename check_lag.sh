#!/bin/bash

echo "========================================================"
echo "PRIMARY NODE: pg_stat_replication"
echo "========================================================"
# Shows the lag as seen by the Primary (write, flush, replay lag)
docker exec pg-primary psql -U postgres -c "
SELECT 
    pid,
    client_addr, 
    application_name, 
    state, 
    sync_state,
    backend_start,
    reply_time,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag, 
    flush_lag, 
    replay_lag
FROM pg_stat_replication;
"

echo ""
echo "========================================================"
echo "PRIMARY NODE: Replication Slots Detailed"
echo "========================================================"
docker exec pg-primary psql -U postgres -c "
SELECT
  slot_name,
  slot_type,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal_or_bytes_behind,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS confirmedLag,
  active,
  pg_current_wal_lsn(),
  confirmed_flush_lsn,
  restart_lsn,
  wal_status,
  safe_wal_size,
  pg_size_pretty(safe_wal_size) 
FROM pg_replication_slots;
"

echo ""
echo "========================================================"
echo "REPLICA NODES: LSN & Time Lag Status"
echo "========================================================"

for replica in pg-replica1 pg-replica2; do
    echo "--- $replica ---"
    docker exec $replica psql -U postgres -c "
    SELECT 
        pg_is_in_recovery() as in_recovery,
        pg_last_wal_receive_lsn() as receive_lsn,
        pg_last_wal_replay_lsn() as replay_lsn,
        pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) as lag_bytes,
        pg_last_xact_replay_timestamp() as last_xact_replay,
        now() - pg_last_xact_replay_timestamp() as time_since_last_xact,
        pg_is_wal_replay_paused() as is_paused
    "
    echo ""
done


echo "Note: 'time_since_last_xact' grows if idle on pg-primary. 'time_lag_seconds' is the actual replication delay in seconds."
