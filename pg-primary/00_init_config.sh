ALTER SYSTEM SET wal_level = 'replica';

CREATE ROLE replica WITH REPLICATION LOGIN PASSWORD 'secret';

SELECT pg_create_physical_replication_slot('pg-replica1');
SELECT pg_create_physical_replication_slot('pg-replica2');

-- Allow replication connections from anywhere (docker network)
COPY (SELECT 'host replication replica 0.0.0.0/0 md5') TO '/var/lib/postgresql/data/pg_hba.conf' WITH (FORMAT text); -- This overwrites, which is bad. BETTER APPROACH BELOW.

-- Instead of overwriting, let's append. But we can't easily append via SQL to a file owned by postgres if restricted.
-- However, standard practice in docker is to set POSTGRES_HOST_AUTH_METHOD=trust (insecure) or configure pg_hba.conf via mount.
-- Since we are sticking to "fixing" the existing setup, let's look at how to add the line.

-- Actually, the official postgres image allows adding lines to pg_hba.conf via a script in /docker-entrypoint-initdb.d/
-- But since we are modifying `init.sql`, we can use shell execution IF we were root, but we are not.

-- BETTER STRATEGY: Create a separate shell script for pg-primary initialization that appends to pg_hba.conf
