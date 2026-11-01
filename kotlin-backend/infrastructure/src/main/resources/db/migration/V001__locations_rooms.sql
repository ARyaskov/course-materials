-- Локации и переговорные. Расширение btree_gist нужно для exclusion constraint в V002.
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE locations (
  id         uuid PRIMARY KEY,
  name       text NOT NULL,
  time_zone  text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE rooms (
  id              uuid PRIMARY KEY,
  location_id     uuid NOT NULL REFERENCES locations (id),
  name            text NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
  capacity        int  NOT NULL CHECK (capacity BETWEEN 1 AND 200),
  price_per_hour  numeric(12, 2) NOT NULL CHECK (price_per_hour >= 0),
  currency        char(3) NOT NULL DEFAULT 'RUB',
  amenities       jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX rooms_location_idx ON rooms (location_id);
CREATE INDEX rooms_amenities_gin ON rooms USING gin (amenities);
