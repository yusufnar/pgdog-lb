#!/bin/bash
set -e

echo "Starting PgDog..."

# Show config for debugging
echo "=== PgDog Configuration ==="
grep -E "host|port|servers|pool_size|default_role|load_balancing" /etc/pgdog/pgdog.toml | head -15

# Copy template if not exists (in case of volume mounts overwriting /etc/pgdog)
if [ ! -f /etc/pgdog/pgdog.toml.template ]; then
    cp /pgdog.toml.template /etc/pgdog/pgdog.toml.template
fi

chmod +x /monitor_lag.sh
/monitor_lag.sh > /var/log/pgdog_monitor.log 2>&1 &

# Start PgDog
exec pgdog -c /etc/pgdog/pgdog.toml -u /etc/pgdog/users.toml run

