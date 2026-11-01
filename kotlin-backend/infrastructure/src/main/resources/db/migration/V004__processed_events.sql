-- Идемпотентные consumer-ы: отметка обработки в одной транзакции с эффектом.
CREATE TABLE processed_events (
  event_id     uuid NOT NULL,
  consumer     text NOT NULL,          -- разные consumer-ы обрабатывают одно событие независимо
  processed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, consumer)
);

-- Очередь уведомлений: эффект consumer-а — запись, отправку делает NotificationDispatcher
CREATE TABLE notification_outbox (
  id        uuid PRIMARY KEY,           -- = event_id: второй слой дедупликации
  member_id uuid NOT NULL,
  booking_id uuid NOT NULL,
  template  text NOT NULL,
  params    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at   timestamptz
);

CREATE INDEX notification_outbox_unsent_idx ON notification_outbox (created_at) WHERE sent_at IS NULL;
