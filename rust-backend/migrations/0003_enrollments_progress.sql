CREATE TABLE enrollments (
    id         uuid PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    course_id  uuid NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
    -- EnrollmentSource as JSONB: {"kind":"purchase","purchase_id":"..."}
    source     jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, course_id)
);

CREATE INDEX enrollments_course_id_idx ON enrollments (course_id);

CREATE TABLE lesson_progress (
    user_id      uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    lesson_id    uuid NOT NULL REFERENCES lessons (id) ON DELETE CASCADE,
    completed_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, lesson_id)
);

CREATE TABLE certificates (
    user_id   uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    course_id uuid NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
    code      text NOT NULL UNIQUE,
    issued_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, course_id)
);
