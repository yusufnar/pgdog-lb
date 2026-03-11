# PgDog PostgreSQL Read Load Balancing Setup

This project demonstrates **read load balancing** for PostgreSQL using **PgDog** and Docker Compose. It distributes SELECT queries across multiple streaming replicas while directing all write operations to the primary server.

> **Note**: This setup focuses on **read scaling** and **connection pooling**. It does not include automatic primary failover (promoting a replica to primary).

## 🏗️ Architecture

```
                    ┌─────────────────┐
                    │   Application   │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │     PgDog       │ ← Port 6432 (Load Balancer)
                    │  (Connection    │
                    │   Pooler +      │
                    │   Read LB)      │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│   pg-primary    │ │   pg-replica1    │ │   pg-replica2    │
│  (Write Only)   │ │   (Read Only)    │ │   (Read Only)    │
│ primary_reads=  │ │   (replica)      │ │   (replica)      │
│     false       │ │                  │ │                  │
└─────────────────┘ └──────────────────┘ └──────────────────┘
```

## ✨ Features

- **⚖️ Read Load Balancing**: SELECT queries distributed randomly across replicas (primary excluded)
- **🔄 Streaming Replication**: WAL-based replication using physical replication slots
- **🏥 Health Check**: Backend health monitoring with auto-ban on failure
- **🔁 Auto Recovery**: Recovered replicas automatically un-banned and re-added to the pool
- **🏊 Connection Pooling**: Transaction-level pooling with configurable pool size
- **📊 Prometheus**: Built-in metrics exporter on port 9930
- **🔀 Read/Write Splitting**: Query parser automatically routes SELECTs to replicas, writes to primary
- **🐳 Official Docker Image**: `ghcr.io/pgdogdev/pgdog:main` (ARM64 & AMD64 compatible)

## 🐳 Container Images

| Container | Image | Description |
|-----------|-------|-------------|
| pg-primary | `postgres:17` | Official PostgreSQL 17 image (primary) |
| pg-replica1 | `postgres:17` | Official PostgreSQL 17 image (streaming replica) |
| pg-replica2 | `postgres:17` | Official PostgreSQL 17 image (streaming replica) |
| pgdog-read | `ghcr.io/pgdogdev/pgdog:main` | PgDog connection pooler + load balancer |

## 📋 Prerequisites

- Docker & Docker Compose
- psql client (for test scripts)

## 🚀 Getting Started

### 1. Start the Cluster

```bash
docker-compose up -d --build
```

This starts:
- `pg-primary` - Primary PostgreSQL (Port 5432)
- `pg-replica1` - Streaming replica
- `pg-replica2` - Streaming replica
- `pgdog-read` - PgDog load balancer (Port 6432)

### 2. Check Cluster Status

```bash
# PgDog admin - pool status
PGPASSWORD=admin psql -h localhost -p 6432 -U admin -d pgdog -c "SHOW POOLS"

# PgDog admin - database status
PGPASSWORD=admin psql -h localhost -p 6432 -U admin -d pgdog -c "SHOW DATABASES"
```

## 📡 Connection

```bash
# Via PgDog (recommended for reads)
PGPASSWORD=secret psql -h localhost -p 6432 -U postgres -d appdb

# Direct to Primary (for writes/admin)
PGPASSWORD=secret psql -h localhost -p 5432 -U postgres -d appdb
```

## 🧪 Test & Monitor Scripts

| Script | Description |
|--------|-------------|
| `./monitor_load_balancing.sh` | Real-time query distribution monitor |
| `./monitor_connections.sh` | Backend connection stats (idle/active) |
| `./check_lag.sh` | Detailed replication lag info |
| `./check_replication.sh` | Full replication test |
| `./check_pgdog_nodes.sh` | PgDog pool & server status |
| `./test_failover_timing.sh` | Failover detection timing |
| `./test_replica_lag.sh` | Test lag detection on one replica |
| `./test_replica_down.sh` | Test replica down scenario |
| `./test_both_replicas_down.sh` | Test all replicas down |
| `./test_both_replicas_lag.sh` | Test lag on all replicas |

## ⚙️ Configuration

### PgDog Settings (pgdog/pgdog.toml)

| Parameter | Value | Description |
|-----------|-------|-------------|
| `pool_mode` | `transaction` | Transaction-level connection pooling |
| `pool_size` | 20 | Max connections per user to backends |
| `load_balancing_mode` | `random` | Random distribution across replicas |
| `default_role` | `replica` | Default target for queries |
| `query_parser_enabled` | `true` | Parse queries for read/write splitting |
| `query_parser_read_write_splitting` | `true` | Route SELECTs to replicas, writes to primary |
| `primary_reads_enabled` | `false` | Primary excluded from read queries |
| `healthcheck_delay` | `1000` | Health check interval (1 second) |
| `healthcheck_timeout` | `2000` | Health check timeout (2 seconds) |
| `ban_time` | `10` | Ban duration for failed servers (seconds) |

### Server Configuration

Primary is excluded from read queries (`primary_reads_enabled = false`):
```toml
[pools.appdb.shards.0]
servers = [
    ["pg-primary", 5432, "primary"],   # write only
    ["pg-replica1", 5432, "replica"],   # read
    ["pg-replica2", 5432, "replica"]    # read
]
```

### ⚠️ PgPool vs PgDog Differences

| Feature | PgPool-II | PgDog |
|---------|-----------|-------|
| Replication lag detection | ✅ Built-in (`delay_threshold`) | ❌ Not supported |
| Auto failback | ✅ `auto_failback = on` | ✅ Auto un-ban after `ban_time` |
| Weight-based LB | ✅ Per-backend weights | ❌ Random or LOC mode |
| Admin interface | `SHOW POOL_NODES` | `SHOW POOLS` / `SHOW DATABASES` |
| Connection pooling | Process-based | Thread-based (more efficient) |
| Config format | `.conf` (key=value) | `.toml` |

> **Note**: PgDog does not have built-in replication lag detection. If a replica is lagging but still healthy, it will continue to receive read queries. For lag-aware routing, an external monitoring solution would be needed.

## 📁 Project Structure

```
pgdog-lb/
├── docker-compose.yml          # Container orchestration
├── README.md
│
├── pg-primary/                 # Primary PostgreSQL
│   ├── init.sql                # Replication user, slots, test table
│   ├── 01_hba.sh               # pg_hba.conf settings
│   └── postgresql.conf
│
├── replica/                    # Replica configuration
│   ├── init_replica.sh         # Base backup and replication setup
│   ├── postgresql.conf
│   └── recovery.conf
│
├── pgdog/                      # PgDog Load Balancer
│   ├── Dockerfile              # Official PgDog image
│   ├── entrypoint.sh           # Startup script
│   └── pgdog.toml              # Full configuration
│
└── scripts (root)
    ├── monitor_load_balancing.sh   # Real-time LB monitor
    ├── monitor_connections.sh      # Connection stats monitor
    ├── check_lag.sh                # Replication lag check
    ├── check_replication.sh        # Full replication test
    ├── check_pgdog_nodes.sh        # PgDog pool status
    ├── test_failover_timing.sh     # Failover timing test
    ├── test_replica_lag.sh         # Lag detection test
    ├── test_replica_down.sh        # Replica down test
    ├── test_both_replicas_down.sh  # All replicas down test
    └── test_both_replicas_lag.sh   # All replicas lag test
```

## 🔧 Troubleshooting

### View Logs

```bash
docker-compose logs -f pgdog-read
docker-compose logs -f pg-primary
```

### Reset Everything

```bash
docker-compose down -v
docker-compose up -d --build
```

### Check Replication Slots

```bash
docker exec pg-primary psql -U postgres -c "SELECT * FROM pg_replication_slots;"
```

### PgDog Admin Commands

```bash
# Connect to PgDog admin database
PGPASSWORD=admin psql -h localhost -p 6432 -U admin -d pgdog

# Useful admin commands:
# SHOW POOLS;      - Pool statistics
# SHOW DATABASES;  - Database configuration
# SHOW VERSION;    - PgDog version
```

## 📚 References

- [PgDog GitHub](https://github.com/postgresml/pgdog)
- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html)

## 📄 License

This project is intended for educational and development purposes.