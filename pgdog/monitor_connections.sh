#!/bin/bash
# monitor_connections.sh - Monitors active connection counts on primary and replicas.
# Runs in a loop, printing a summary every CHECK_INTERVAL seconds.

CHECK_INTERVAL=2
PRIMARY_HOST="pg-primary"
REPLICA_HOSTS=("pg-replica1" "pg-replica2")
ALL_HOSTS=("$PRIMARY_HOST" "${REPLICA_HOSTS[@]}")
DB_USER="postgres"

export PGPASSWORD="secret"

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

get_connection_count() {
    local host=$1
    # Total active connections (excluding system connections)
    local count=$(psql -h "$host" -U "$DB_USER" -p 5432 -Atc \
        "SELECT count(*) FROM pg_stat_activity WHERE datname IS NOT NULL AND pid <> pg_backend_pid();" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$count" ]; then
        echo "-1"
    else
        echo "$count"
    fi
}

get_connection_details() {
    local host=$1
    # Breakdown by state
    psql -h "$host" -U "$DB_USER" -p 5432 -Atc \
        "SELECT state, count(*) FROM pg_stat_activity WHERE datname IS NOT NULL AND pid <> pg_backend_pid() GROUP BY state ORDER BY count DESC;" 2>/dev/null
}

get_max_connections() {
    local host=$1
    psql -h "$host" -U "$DB_USER" -p 5432 -Atc "SHOW max_connections;" 2>/dev/null
}

get_role() {
    local host=$1
    local is_recovery=$(psql -h "$host" -U "$DB_USER" -p 5432 -Atc "SELECT pg_is_in_recovery();" 2>/dev/null)
    if [ "$is_recovery" = "t" ]; then
        echo "replica"
    elif [ "$is_recovery" = "f" ]; then
        echo "primary"
    else
        echo "unknown"
    fi
}

echo -e "${BOLD}Starting PgDog Connection Monitor...${NC}"
echo -e "Monitoring: ${CYAN}${ALL_HOSTS[*]}${NC}"
echo -e "Interval: ${CHECK_INTERVAL}s"
echo ""

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD} Connection Report - ${TIMESTAMP}${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"

    TOTAL_CONNECTIONS=0

    for host in "${ALL_HOSTS[@]}"; do
        count=$(get_connection_count "$host")
        
        if [ "$count" = "-1" ]; then
            echo -e "  ${RED}✗ ${host}${NC} — ${RED}DOWN / Unreachable${NC}"
            continue
        fi

        role=$(get_role "$host")
        max_conn=$(get_max_connections "$host")
        details=$(get_connection_details "$host")

        # Color based on usage percentage
        if [ -n "$max_conn" ] && [ "$max_conn" -gt 0 ]; then
            pct=$((count * 100 / max_conn))
            if [ "$pct" -ge 80 ]; then
                COLOR=$RED
            elif [ "$pct" -ge 50 ]; then
                COLOR=$YELLOW
            else
                COLOR=$GREEN
            fi
            usage_str="${COLOR}${count}/${max_conn} (${pct}%)${NC}"
        else
            usage_str="${GREEN}${count}${NC}"
        fi

        # Role label
        if [ "$role" = "primary" ]; then
            role_label="${YELLOW}[PRIMARY]${NC}"
        elif [ "$role" = "replica" ]; then
            role_label="${CYAN}[REPLICA]${NC}"
        else
            role_label="[?]"
        fi

        echo -e "  ${GREEN}✓${NC} ${BOLD}${host}${NC} ${role_label}  Connections: ${usage_str}"

        # Print state breakdown
        if [ -n "$details" ]; then
            while IFS='|' read -r state cnt; do
                state=${state:-"null"}
                echo -e "      ${state}: ${cnt}"
            done <<< "$details"
        fi

        TOTAL_CONNECTIONS=$((TOTAL_CONNECTIONS + count))
    done

    echo -e "${BOLD}───────────────────────────────────────────────────────${NC}"
    echo -e "  Total connections across all nodes: ${BOLD}${TOTAL_CONNECTIONS}${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo ""

    sleep "$CHECK_INTERVAL"
done
