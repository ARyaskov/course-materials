# Pipelines

Each `*.json` file describes one pipeline (see `src/rota/model/pipeline.hpp` for the schema):

* `name`, `description`, `schedule` (five-field cron or `@hourly`/`@daily`/...), `enabled`, `max_parallel`;
* `tasks[]`: `name`, `executor` (`process` or a plugin name), `command`, `args`, `env`,
  `depends_on`, `timeout`, `expected_duration`, `retry { max_attempts, backoff }`;
* `webhooks[]`: URLs that receive `run.started` / `run.finished` events.

Task names use 1–100 ASCII letters, digits, `-` or `_`; separators and dot components
are rejected because task names are used in working-directory paths.

An argument beginning with `{project_dir}/` resolves against the directory from which
`rotad` was started, before switching into the per-attempt working directory.
`nightly-report.json` uses this for the included Python scripts. They generate synthetic
input and write `data/nightly-report/report.json`; no real warehouse is contacted.
The command `python` must be Python 3.10 or newer (Linux: install `python-is-python3`).

`smoke.json` uses `cmd /c` and therefore runs on Windows; `smoke.linux.json.example` is the
POSIX twin — rename it to `smoke.json` on Linux/macOS.

Note for plugin authors on POSIX: `rotad` never writes to a child's stdin, but a plugin that
pipes data into a process must ignore `SIGPIPE` (or use `MSG_NOSIGNAL`), otherwise a peer that
exits early kills the daemon.

Timeouts terminate the task's own process only: a task that leaves background children
(`start /b ...`, `cmd &`) keeps its stdout pipe open until they exit, and the daemon cannot kill
them. Wrap long-running helpers so that they exit with the task.
