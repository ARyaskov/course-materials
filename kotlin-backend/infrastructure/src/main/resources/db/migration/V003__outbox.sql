-- Transactional outbox: событие пишется той же транзакцией, что и изменение; relay переносит в Kafka.
CREATE TABLE outbox (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   -- порядок публикации
  event_id      uuid NOT NULL UNIQUE,                               -- дедупликация на consumer-е
  aggregate_id  uuid NOT NULL,                                      -- ключ партиции Kafka
  event_type    text NOT NULL,
  payload       jsonb NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  published_at  timestamptz
);

-- Relay читает только неопубликованные, по порядку id
CREATE INDEX outbox_unpublished_idx ON outbox (id) WHERE published_at IS NULL;
