# PgDog Dockerfile
# Official PgDog image - ARM64 & AMD64 compatible

FROM ghcr.io/pgdogdev/pgdog:main

# Copy configuration
COPY pgdog.toml /etc/pgdog/pgdog.toml

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# PgDog default port + Prometheus exporter
EXPOSE 6432 9930

ENTRYPOINT ["/entrypoint.sh"]
