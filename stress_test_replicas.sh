#!/usr/bin/env bash

# --- CONFIG ---
REPLICAS=("pg-replica1" "pg-replica2")
DB_USER="postgres"
DB_NAME="appdb"
QPS=1000
WORKERS=20  # Number of persistent connections

# Replication lag query
QUERY="SELECT /*stress_test_replicas.sh*/ EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS replication_lag;"

# --- SETUP ---
# Create temp directory for FIFOs
FIFO_DIR=$(mktemp -d /tmp/pg_stress_XXXXXX)
declare -a OPENER_PIDS

cleanup() {
    echo -e "\n\n[$(date +%H:%M:%S)] Cleaning up background processes and pipes..."
    # Kill background psql, openers, and worker processes
    # pkill -P $$ is effective for killing children of the current script
    pkill -P $$ > /dev/null 2>&1
    # Explicitly kill opener PIDs just in case
    for pid in "${OPENER_PIDS[@]}"; do
        kill "$pid" > /dev/null 2>&1
    done
    # Remove temp directory
    rm -rf "$FIFO_DIR"
    echo "[$(date +%H:%M:%S)] Done."
    exit
}

# Catch signals for clean exit
trap cleanup SIGINT SIGTERM EXIT

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      PERSISTENT CONNECTION STRESS TESTER (Pure Bash)         ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║ Target Replicas: ${REPLICAS[*]}                      ║"
echo "║ Target QPS:      $QPS                                        ║"
echo "║ Parallel Workers: $WORKERS (Persistent Connections)            ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Start persistent psql processes
echo "[$(date +%H:%M:%S)] Establishing $WORKERS persistent connections..."
for ((i=0; i<WORKERS; i++)); do
    replica_id=$((i % ${#REPLICAS[@]}))
    target_replica=${REPLICAS[$replica_id]}
    
    fifo="$FIFO_DIR/worker_$i"
    mkfifo "$fifo"
    
    # Start psql in background reading from FIFO
    docker exec -i "$target_replica" psql -U "$DB_USER" -d "$DB_NAME" -At < "$fifo" > /dev/null 2>&1 &
    
    # KEEP PIPE OPEN: In Bash 3.2, we use a background process to hold the pipe open
    # This ensures psql doesn't receive EOF until we kill this background process.
    ( sleep 999999 > "$fifo" ) &
    OPENER_PIDS+=("$!")
done

echo "[$(date +%H:%M:%S)] All connections established."

# --- WORKER LOOP ---
SLEEP_INTERVAL=$(echo "scale=4; $WORKERS / $QPS" | bc -l)

worker() {
    local fifo=$1
    while true; do
        # Send query through the persistent pipe
        # Because the 'opener' process is holding the pipe, this won't trigger EOF
        echo "$QUERY" > "$fifo"
        sleep "$SLEEP_INTERVAL"
    done
}

# Launch worker subshells to feed the pipes
for ((i=0; i<WORKERS; i++)); do
    worker "$FIFO_DIR/worker_$i" &
done

# Progress display
count=0
while true; do
    printf "\r[$(date +%H:%M:%S)] Total queries initiated (approx): %d..." "$count"
    count=$((count + QPS))
    sleep 1
done
