#!/usr/bin/env bash

# --- CONFIG ---
REPLICAS=("pg-replica1" "pg-replica2")
DB_USER="postgres"
DB_NAME="appdb"
QPS=100
WORKERS=20  # Daha verimli bir paralellik için worker sayısını optimize ettik

# Replication lag query
QUERY="SELECT /*stress_test_replicas_new_conn.sh*/ EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS replication_lag;"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          REPLICA STRESS TESTER (Lag Monitoring Load)         ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║ Target Replicas: ${REPLICAS[*]}                      ║"
echo "║ Target QPS:      $QPS                                        ║"
echo "║ Parallel Workers: $WORKERS                                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Her worker'ın beklemesi gereken süre (saniye cinsinden)
# Örn: 100 QPS / 20 Worker = Her worker saniyede 5 sorgu -> 0.2s bekleme
SLEEP_INTERVAL=$(echo "scale=4; $WORKERS / $QPS" | bc -l)

worker() {
    local worker_id=$1
    local replica_id=$((worker_id % ${#REPLICAS[@]}))
    local target_replica=${REPLICAS[$replica_id]}
    
    while true; do
        # Async query gönder (Docker üzerinden)
        docker exec "$target_replica" psql -U "$DB_USER" -d "$DB_NAME" -Atc "$QUERY" > /dev/null 2>&1 &
        
        # Hedeflenen hıza ulaşmak için bekle
        sleep "$SLEEP_INTERVAL"
    done
}

# --- MAIN ---

echo "[$(date +%H:%M:%S)] Stress test başlatılıyor..."

# Workers başlat
for ((i=0; i<WORKERS; i++)); do
    worker "$i" &
done

# Graceful shutdown
trap "echo -e '\nStopping... Cleaning up background processes.'; kill 0; exit" SIGINT SIGTERM

# Canlı sayaç (Basit bir görsel feedback)
count=0
while true; do
    printf "\r[$(date +%H:%M:%S)] Toplam yaklaşık gönderilen: %d sorgu..." "$count"
    count=$((count + QPS))
    sleep 1
done
