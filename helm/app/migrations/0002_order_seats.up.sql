-- Reservation items are retained after expiry for the order history.
CREATE TABLE IF NOT EXISTS order_seats (
    order_id uuid NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
    seat_id uuid NOT NULL REFERENCES seats (id),
    PRIMARY KEY (order_id, seat_id)
);
CREATE INDEX IF NOT EXISTS order_seats_seat_idx ON order_seats (seat_id);
