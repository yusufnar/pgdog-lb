#!/bin/bash

# Port 6432 is exposed for PgDog in docker-compose
PGDOG_PORT=6432
PGDOG_HOST=127.0.0.1
USER=postgres
DB=appdb

echo "========================================================"
echo "1. Current PgDog Pool Status (SHOW POOLS)"
echo "========================================================"
# Connect to PgDog admin and ask for status
PGPASSWORD=admin psql -h $PGDOG_HOST -p $PGDOG_PORT -U admin -d pgdog -c "SHOW POOLS"

echo ""
echo "========================================================"
echo "2. Current PgDog Server Status (SHOW DATABASES)"
echo "========================================================"
PGPASSWORD=admin psql -h $PGDOG_HOST -p $PGDOG_PORT -U admin -d pgdog -c "SHOW DATABASES"

echo ""
echo "========================================================"
echo "3. Testing Load Balancing (Executing 10 Queries)"
echo "========================================================"
# Run 10 simple queries to check which node IP responds
for i in {1..10}; do
    SERVER_IP=$(PGPASSWORD=secret psql -h $PGDOG_HOST -p $PGDOG_PORT -U $USER -d $DB -t -c "SELECT inet_server_addr();" | tr -d '[:space:]')
    echo "Query $i handled by: $SERVER_IP"
done

echo ""
echo "Note: Compare IPs with 'docker inspect' to identify container names."
