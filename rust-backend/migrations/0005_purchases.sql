CREATE TABLE purchases (
    id                  uuid PRIMARY KEY,
    user_id             uuid NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    course_id           uuid NOT NULL REFERENCES courses (id) ON DELETE RESTRICT,
    amount              numeric(12, 2) NOT NULL CHECK (amount > 0),
    currency            text NOT NULL CHECK (currency IN ('USD', 'EUR')),
    status              text NOT NULL CHECK (status IN ('pending', 'paid', 'failed', 'refunded')),
    provider_payment_id text,
    idempotency_key     text NOT NULL,
    failure_reason      text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    -- the same client key for the same user always maps to the same purchase
    UNIQUE (user_id, idempotency_key)
);

CREATE UNIQUE INDEX purchases_provider_payment_id_key ON purchases (provider_payment_id) WHERE provider_payment_id IS NOT NULL;
CREATE INDEX purchases_user_course_idx ON purchases (user_id, course_id);

-- Every webhook delivery is recorded once; duplicates hit the UNIQUE index and
-- are acknowledged without side effects.
CREATE TABLE billing_events (
    provider_event_id text PRIMARY KEY,
    event_type        text NOT NULL,
    payload           jsonb NOT NULL,
    received_at       timestamptz NOT NULL DEFAULT now()
);
