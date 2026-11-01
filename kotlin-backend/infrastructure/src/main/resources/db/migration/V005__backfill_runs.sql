-- Checkpoint backfill-задач: повторный запуск с тем же run_id продолжает с курсора.
CREATE TABLE backfill_runs (
  run_id       text PRIMARY KEY,
  cursor_at    timestamptz,
  cursor_id    uuid,
  processed    bigint NOT NULL DEFAULT 0,
  started_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

-- Загрузка комнат по дням: заполняется backfill-ом (присваивание за день) и consumer-ом событий
CREATE TABLE room_utilization (
  room_id        uuid NOT NULL REFERENCES rooms (id),
  day            date NOT NULL,
  minutes_booked bigint NOT NULL DEFAULT 0,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (room_id, day)
);
