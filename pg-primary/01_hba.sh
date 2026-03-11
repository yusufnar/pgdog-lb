#!/bin/bash
echo "host replication replica 0.0.0.0/0 trust" >> "$PGDATA/pg_hba.conf"
echo "host all all 0.0.0.0/0 trust" >> "$PGDATA/pg_hba.conf" # For simplicity in this demo environment
