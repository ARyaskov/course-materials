-- Брони. Слот хранится как tstzrange (полуоткрытый [start, end)) — exclusion constraint
-- запрещает пересечение активных броней одной комнаты на уровне базы.
CREATE TABLE bookings (
  id            uuid PRIMARY KEY,
  room_id       uuid NOT NULL REFERENCES rooms (id),
  member_id     uuid NOT NULL,
  slot          tstzrange NOT NULL,
  status        text NOT NULL CHECK (status IN ('PENDING', 'CONFIRMED', 'CANCELLED', 'EXPIRED', 'NO_SHOW')),
  expires_at    timestamptz,
  payment_id    text,
  cancel_reason text,
  cancelled_at  timestamptz,
  version       bigint NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL,
  updated_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT bookings_slot_not_empty CHECK (NOT isempty(slot) AND lower_inc(slot) AND NOT upper_inc(slot)),
  -- Инварианты sealed-статуса, выраженные схемой: у PENDING есть срок, у CONFIRMED — платёж, у CANCELLED — причина
  CONSTRAINT bookings_pending_has_expiry CHECK (status <> 'PENDING' OR expires_at IS NOT NULL),
  CONSTRAINT bookings_confirmed_has_payment CHECK (status <> 'CONFIRMED' OR payment_id IS NOT NULL),
  CONSTRAINT bookings_cancelled_has_reason CHECK (status <> 'CANCELLED' OR (cancel_reason IS NOT NULL AND cancelled_at IS NOT NULL)),
  -- Последняя линия защиты от double booking: две активные брони одной комнаты не пересекаются
  CONSTRAINT bookings_no_overlap EXCLUDE USING gist (room_id WITH =, slot WITH &&)
    WHERE (status IN ('PENDING', 'CONFIRMED'))
);

-- Запросы занятости по комнате и окну; частичный индекс только по активным
CREATE INDEX bookings_room_slot_active_idx ON bookings USING gist (room_id, slot) WHERE status IN ('PENDING', 'CONFIRMED');
-- Список броней участника с keyset-пагинацией по (created_at DESC, id DESC)
CREATE INDEX bookings_member_created_idx ON bookings (member_id, created_at DESC, id DESC);
-- Фоновая задача истечения: только PENDING, по сроку
CREATE INDEX bookings_pending_expires_idx ON bookings (expires_at) WHERE status = 'PENDING';
