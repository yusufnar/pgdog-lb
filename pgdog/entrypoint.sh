#!/bin/bash
set -e

echo "Starting PgDog..."

# Show config for debugging
echo "=== PgDog Configuration ==="
grep -E "host|port|servers|pool_size|default_role|load_balancing" /etc/pgdog/pgdog.toml | head -15

# Start PgDog
exec pgdog -c /etc/pgdog/pgdog.toml run
