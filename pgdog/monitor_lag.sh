#!/bin/bash
# monitor_lag.sh - Monitors replication lag and updates PgDog config dynamically.
# Threshold for replica lag in milliseconds.
LAG_THRESHOLD=2000
CHECK_INTERVAL=1
CONFIG_TEMPLATE="/etc/pgdog/pgdog.toml.template"
CONFIG_FILE="/etc/pgdog/pgdog.toml"
DB_NAME="appdb"
PRIMARY_HOST="pg-primary"

# Map: Hostname in Docker network -> application_name in pg_stat_replication
declare -A REPLICA_MAP
REPLICA_MAP["pg-replica1"]="pg_replica1"
REPLICA_MAP["pg-replica2"]="pg_replica2"

# Function to get lag in ms. Returns -1 if down.
get_lag_ms() {
    local host=$1
    local app_name=${REPLICA_MAP[$host]}
    
    # We check if the node is alive first
    if ! pg_isready -h "$host" -p 5432 -t 1 > /dev/null 2>&1; then
        return
    fi

    # Query the primary for this replica's lag 
    # pg_stat_replication.replay_lag is an interval.
    # Convert interval to ms. 
    # We check using application_name which is more reliable.
    local lag=$(psql -h "$PRIMARY_HOST" -U postgres -Atc "SELECT EXTRACT(EPOCH FROM replay_lag) * 1000 FROM pg_stat_replication WHERE application_name = '$app_name'" 2>/dev/null)
    
    if [ -z "$lag" ]; then
        # Check if the replica is even connected to primary
        local is_connected=$(psql -h "$PRIMARY_HOST" -U postgres -Atc "SELECT count(*) FROM pg_stat_replication WHERE application_name = '$app_name'")
        if [ "$is_connected" -eq 0 ]; then
            echo -1
        else
            # Connected but lag is 0 (shows as null sometimes if no activity)
            echo 0
        fi
    else
        # Round to integer
        printf "%.0f" "$lag"
    fi
}

update_config() {
    local active_replicas=("$@")
    local use_primary=false
    
    # If no healthy replicas, or if specified by logic, we add primary.
    if [ ${#active_replicas[@]} -eq 0 ]; then
        use_primary=true
    fi

    cp "$CONFIG_TEMPLATE" "$CONFIG_FILE.new"

    # Add Primary if needed
    if [ "$use_primary" = true ]; then
        echo "Adding PRIMARY to config as fallback"
        cat >> "$CONFIG_FILE.new" <<EOF

[[databases]]
name = "$DB_NAME"
database_name = "$DB_NAME"
host = "$PRIMARY_HOST"
port = 5432
role = "primary"
shard = 0
EOF
    fi

    # Add active Replicas
    for replica in "${active_replicas[@]}"; do
        echo "Adding $replica to config"
        cat >> "$CONFIG_FILE.new" <<EOF

[[databases]]
name = "$DB_NAME"
database_name = "$DB_NAME"
host = "$replica"
port = 5432
role = "replica"
shard = 0
EOF
    done

    # Check if config actually changed
    if ! diff "$CONFIG_FILE" "$CONFIG_FILE.new" > /dev/null 2>&1; then
        mv "$CONFIG_FILE.new" "$CONFIG_FILE"
        echo "Config changed [${active_replicas[*]}] [Primary:$use_primary], reloading PgDog..."
        pkill -HUP pgdog
    else
        rm "$CONFIG_FILE.new"
    fi
}

echo "Starting PgDog Lag Monitor..."
export PGPASSWORD="secret"

while true; do
    healthy_replicas=()
    
    for replica in "${!REPLICA_MAP[@]}"; do
        lag=$(get_lag_ms "$replica")
        if [ ! -z "$lag" ] && [ "$lag" != "-1" ] && [ "$lag" -lt "$LAG_THRESHOLD" ]; then
            healthy_replicas+=("$replica")
        else
            echo "$replica is UNHEALTHY or lag too high (lag: ${lag:-N/A}ms)"
        fi
    done

    update_config "${healthy_replicas[@]}"
    sleep "$CHECK_INTERVAL"
done
