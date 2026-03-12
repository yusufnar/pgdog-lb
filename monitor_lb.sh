#!/bin/bash

# Load Balancing Monitor Script
# Runs 10 queries per second and shows which nodes handle them

PGDOG_PORT=6432
PGDOG_HOST=127.0.0.1
USER=postgres
DB=appdb

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          PGDOG LOAD BALANCING MONITOR                       ║"
echo "║     Press Ctrl+C to stop                                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Show current node IPs
echo "Current Nodes:"
docker ps --format "{{.Names}}" | grep -E "^pg-" | while read name; do
    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name" 2>/dev/null)
    echo "  $name -> $ip"
done
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get node name from IP
get_node() {
    local ip=$1
    docker ps --format "{{.Names}}" | grep -E "^pg-" | while read name; do
        node_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name" 2>/dev/null)
        if [ "$node_ip" = "$ip" ]; then
            echo "$name"
            return
        fi
    done
    echo "$ip"
}

while true; do
    timestamp=$(date +%H:%M:%S)
    
    results=""
    replica1_count=0
    replica2_count=0
    primary_count=0
    error_count=0
    
    for i in {1..10}; do
        ip=$(PGPASSWORD=secret psql -h $PGDOG_HOST -p $PGDOG_PORT -U $USER -d $DB -t -c "SELECT inet_server_addr();" 2>/dev/null | awk -F'|' '{print $1}' | tr -d '[:space:]')
        
        if [ -n "$ip" ]; then
            node=$(get_node "$ip")
            short_name=$(echo "$node" | sed 's/pg-//')
            results="${results}${short_name:0:4} "
            
            case "$node" in
                *replica1*) replica1_count=$((replica1_count + 1)) ;;
                *replica2*) replica2_count=$((replica2_count + 1)) ;;
                *primary*) primary_count=$((primary_count + 1)) ;;
            esac
        else
            results="${results}ERR "
            error_count=$((error_count + 1))
        fi
    done
    
    # Build summary
    summary=""
    [ $replica1_count -gt 0 ] && summary="${summary}r1:${replica1_count} "
    [ $replica2_count -gt 0 ] && summary="${summary}r2:${replica2_count} "
    [ $primary_count -gt 0 ] && summary="${summary}pri:${primary_count} "
    [ $error_count -gt 0 ] && summary="${summary}err:${error_count} "
    
    printf "[%s] %s| %s\n" "$timestamp" "$results" "$summary"
    
    sleep 1
done
