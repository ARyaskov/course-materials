-- Transactional outbox: written in the same transaction as the business
-- change, drained by the worker with SELECT ... FOR UPDATE SKIP LOCKED.
CREATE TABLE outbox_events (
    id              uuid PRIMARY KEY,
    event_type      text NOT NULL,
    payload         jsonb NOT NULL,
    status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'done', 'dead')),
    attempts        integer NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL DEFAULT now(),
    locked_until    timestamptz,
    last_error      text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    processed_at    timestamptz
);

CREATE INDEX outbox_events_pending_idx ON outbox_events (next_attempt_at) WHERE status IN ('pending', 'processing');

CREATE TABLE notifications (
    id         uuid PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    event      jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    read_at    timestamptz
);

CREATE INDEX notifications_user_created_idx ON notifications (user_id, created_at DESC);
