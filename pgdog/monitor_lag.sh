#!/bin/bash
# monitor_lag.sh - Monitors replication lag and updates PgDog config dynamically.
# Threshold for replica lag in milliseconds.
LAG_THRESHOLD=1000
CHECK_INTERVAL=1
CONFIG_TEMPLATE="/etc/pgdog/pgdog.toml.template"
CONFIG_FILE="/etc/pgdog/pgdog.toml"
DB_NAME="appdb"
PRIMARY_HOST="pg-primary"

# List of replicas to monitor
REPLICAS=("pg-replica1" "pg-replica2")

# Function to get lag in ms. Returns -1 if down.
get_lag_ms() {
    local host=$1
    
    # We check if the node is alive first
    if ! pg_isready -h "$host" -p 5432 -t 1 > /dev/null 2>&1; then
        echo -1
        return
    fi

    # Query the replica directly for lag
    local lag=$(psql -h "$host" -U postgres -Atc "SELECT CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE GREATEST(0, EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())) * 1000 END" 2>/dev/null)
    
    if [ -z "$lag" ] || [ "$lag" = "NaN" ]; then
        echo -1
    else
        printf "%.0f" "$lag"
    fi
}

update_config() {
    local healthy_count=$1
    shift
    local replicas=("$@")
    
    # Separate replicas from down replicas (down replicas have empty weight)
    local active_replicas=()
    local down_replicas=()
    for replica_info in "${replicas[@]}"; do
        IFS=':' read -r replica weight <<< "$replica_info"
        if [ -z "$weight" ]; then
            down_replicas+=("$replica")
        else
            active_replicas+=("$replica_info")
        fi
    done
    
    local primary_weight=0
    if [ "$healthy_count" -eq 0 ]; then
        primary_weight=1
    fi

    cp "$CONFIG_TEMPLATE" "$CONFIG_FILE.new"

    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Setting PRIMARY config block with lb_weight=$primary_weight"
    cat >> "$CONFIG_FILE.new" <<EOF

[[databases]]
name = "$DB_NAME"
database_name = "$DB_NAME"
host = "$PRIMARY_HOST"
port = 5432
role = "primary"
shard = 0
lb_weight = $primary_weight
EOF

    # Add only active Replicas
    for replica_info in "${active_replicas[@]}"; do
        IFS=':' read -r replica weight <<< "$replica_info"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Setting REPLICA $replica config block with lb_weight=$weight"
        cat >> "$CONFIG_FILE.new" <<EOF

[[databases]]
name = "$DB_NAME"
database_name = "$DB_NAME"
host = "$replica"
port = 5432
role = "replica"
shard = 0
lb_weight = $weight
EOF
    done

    # Check if config actually changed
    if ! diff "$CONFIG_FILE" "$CONFIG_FILE.new" > /dev/null 2>&1; then
        mv "$CONFIG_FILE.new" "$CONFIG_FILE"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Config changed [PrimaryWeight:$primary_weight, ActiveReplicas:${#active_replicas[@]}], reloading PgDog..."
        pkill -HUP pgdog
    else
        rm "$CONFIG_FILE.new"
    fi
}

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting PgDog Lag Monitor..."
export PGPASSWORD="secret"

while true; do
    healthy_count=0
    replica_weights=()
    
    # Sort replicas to ensure deterministic config generation
    for replica in $(echo "${REPLICAS[@]}" | tr ' ' '\n' | sort); do
        lag=$(get_lag_ms "$replica")
        if [ -n "$lag" ] && [ "$lag" != "-1" ] && [ "$lag" -lt "$LAG_THRESHOLD" ]; then
            replica_weights+=("$replica:1")
            ((healthy_count++))
        elif [ "$lag" = "-1" ]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] 🚨 REPLICA DOWN: $replica is unreachable, removing from config"
            replica_weights+=("$replica:")  # empty weight = remove from config
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] 🚨 LAG DETECTED: $replica lag too high (lag: ${lag:-N/A}ms), setting weight=0"
            replica_weights+=("$replica:0")
        fi
    done

    update_config "$healthy_count" "${replica_weights[@]}"
    sleep "$CHECK_INTERVAL"
done
