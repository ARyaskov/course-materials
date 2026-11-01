-- Pulse: реплицируемая база данных кластера (глава 13).
-- Единственный DDL с ON CLUSTER: дальше все команды в базе pulse реплицируются сами.
CREATE DATABASE IF NOT EXISTS pulse ON CLUSTER pulse_cluster
ENGINE = Replicated('/clickhouse/databases/pulse', '{shard}', '{replica}');

SELECT hostName() AS host, name, engine
FROM clusterAllReplicas('pulse_cluster', system.databases)
WHERE name = 'pulse'
ORDER BY host;
