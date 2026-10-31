CREATE TABLE courses (
    id           uuid PRIMARY KEY,
    author_id    uuid NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    title        text NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
    slug         text NOT NULL,
    description  text NOT NULL DEFAULT '',
    price_amount numeric(12, 2) NOT NULL CHECK (price_amount >= 0),
    currency     text NOT NULL CHECK (currency IN ('USD', 'EUR')),
    status       text NOT NULL CHECK (status IN ('draft', 'published', 'archived')),
    version      integer NOT NULL DEFAULT 1,
    published_at timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX courses_author_id_idx ON courses (author_id);
-- Public catalogue is paginated by (created_at, id) among published courses only.
CREATE INDEX courses_published_created_idx ON courses (created_at DESC, id DESC) WHERE status = 'published';

CREATE TABLE lessons (
    id              uuid PRIMARY KEY,
    course_id       uuid NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
    position        integer NOT NULL CHECK (position >= 1),
    title           text NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
    content_md      text NOT NULL DEFAULT '',
    is_free_preview boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (course_id, position)
);
