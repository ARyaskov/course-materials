-- Базовая схема Tessera: события, места, заказы, билеты.
CREATE TABLE IF NOT EXISTS events (
    id          uuid PRIMARY KEY,
    title       text        NOT NULL,
    starts_at   timestamptz NOT NULL,
    venue       text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS seats (
    id        uuid PRIMARY KEY,
    event_id  uuid        NOT NULL REFERENCES events (id) ON DELETE CASCADE,
    sector    text        NOT NULL,
    row_no    int         NOT NULL,
    seat_no   int         NOT NULL,
    price     numeric(12, 2) NOT NULL,
    UNIQUE (event_id, sector, row_no, seat_no)
);

CREATE TABLE IF NOT EXISTS orders (
    id          uuid PRIMARY KEY,
    event_id    uuid        NOT NULL REFERENCES events (id),
    status      text        NOT NULL CHECK (status IN ('pending', 'paid', 'expired', 'cancelled')),
    total       numeric(12, 2) NOT NULL,
    expires_at  timestamptz NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS orders_pending_expires_idx
    ON orders (expires_at) WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS tickets (
    id          uuid PRIMARY KEY,
    order_id    uuid        NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
    seat_id     uuid        NOT NULL REFERENCES seats (id),
    code        text        NOT NULL UNIQUE,
    checked_in_at timestamptz,
    UNIQUE (seat_id)
);
