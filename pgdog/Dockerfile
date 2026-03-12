# PgDog Dockerfile
# Official PgDog image - ARM64 & AMD64 compatible

FROM ghcr.io/pgdogdev/pgdog:main

# Copy configuration
COPY pgdog.toml /etc/pgdog/pgdog.toml
COPY users.toml /etc/pgdog/users.toml

COPY pgdog.toml.template /pgdog.toml.template
COPY monitor_lag.sh /monitor_lag.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /monitor_lag.sh /entrypoint.sh

# PgDog default port + Prometheus exporter
EXPOSE 6432 9930

ENTRYPOINT ["/entrypoint.sh"]
