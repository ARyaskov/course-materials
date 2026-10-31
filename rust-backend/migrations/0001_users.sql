-- Users: one row per account. Role is text + CHECK instead of a PostgreSQL
-- enum: adding a role is then an ordinary migration, not an ALTER TYPE.
CREATE TABLE users (
    id                uuid PRIMARY KEY,
    email             text NOT NULL,
    display_name      text NOT NULL,
    password_hash     text NOT NULL,
    role              text NOT NULL CHECK (role IN ('student', 'author', 'admin')),
    email_verified_at timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX users_email_key ON users (email);
