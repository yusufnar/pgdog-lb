#!/bin/bash
# Continuous Load Generator
# Inserts a row into 'ynar' table every second to simulate write traffic
# DIRECT CONNECTION TO PRIMARY (Bypassing PgDog)

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║    CONTINUOUS LOAD GENERATOR (Direct Primary)                ║"
echo "║    Press Ctrl+C to stop                                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Create table if not exists (just in case)
docker exec pg-primary psql -U postgres -d appdb -c "CREATE TABLE IF NOT EXISTS ynar (id SERIAL PRIMARY KEY, info TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);" >/dev/null 2>&1

count=0
while true; do
    timestamp=$(date +%Y-%m-%d_%H:%M:%S)
    
    # Insert row directly on Primary container
    docker exec pg-primary psql -U postgres -d appdb -c "INSERT INTO ynar (info) VALUES ('load_test_${timestamp}');" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        count=$((count+1))
        # Clear line and print status
        printf "\r[$(date +%H:%M:%S)] Inserted row #%d... " "$count"
    else
        printf "\r[$(date +%H:%M:%S)] Insert failed! Check pg-primary... "
    fi
    
    sleep 1
done
