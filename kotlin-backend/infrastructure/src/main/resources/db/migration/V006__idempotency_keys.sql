-- Idempotency-Key: (member_id, key) → результат; запись booking_id в транзакции с созданием брони.
CREATE TABLE idempotency_keys (
  member_id       uuid NOT NULL,
  key             text NOT NULL,
  request_hash    text NOT NULL,          -- sha256 метода, пути и тела
  booking_id      uuid,                   -- Replay восстанавливает ответ по актуальному состоянию брони
  response_status int,
  locked_at       timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz,
  expires_at      timestamptz NOT NULL,
  PRIMARY KEY (member_id, key)
);
CREATE INDEX idempotency_keys_expires_idx ON idempotency_keys (expires_at);

-- Естественная идемпотентность: тот же участник не создаст две одинаковые активные брони
CREATE UNIQUE INDEX bookings_member_room_slot_active_uq ON bookings (room_id, member_id, slot) WHERE status IN ('PENDING', 'CONFIRMED');
