ALTER SYSTEM SET wal_level = 'replica';

CREATE ROLE replica WITH REPLICATION LOGIN PASSWORD 'secret';

SELECT pg_create_physical_replication_slot('pg_replica1');
SELECT pg_create_physical_replication_slot('pg_replica2');

CREATE TABLE ynar (
    id SERIAL PRIMARY KEY,
    info TEXT,
    created_at TIMESTAMP DEFAULT now()
);

INSERT INTO ynar (info) VALUES 
('dummy_data_1'),
('dummy_data_2'),
('dummy_data_3');
