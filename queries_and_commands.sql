docker-compose up -d --force-recreate

docker exec pg-replica1 psql -U postgres -d appdb -t -c "SELECT state, query, count(*) FROM pg_stat_activity WHERE application_name = 'psql' group by state, query;"

docker exec pg-replica1 psql -U postgres -d appdb -t -c "SELECT calls, total_exec_time, mean_exec_time, rows, query FROM pg_stat_statements ORDER BY mean_exec_time DESC;"

docker exec pg-primary psql -U postgres -d appdb -c "\dx" 

SELECT calls, total_exec_time, mean_exec_time, rows, query FROM pg_stat_statements  where query ilike '%pg_last_xact_replay_timestamp%' ORDER BY mean_exec_time DESC;