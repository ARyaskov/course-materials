import type { LogLevel, Logger } from '#services/ports.ts';

const ORDER = {
  debug: 10,
  info: 20,
  warn: 30,
  error: 40,
} as const satisfies Record<LogLevel, number>;

const PREFIX = {
  debug: '·',
  info: 'i',
  warn: '!',
  error: 'x',
} as const satisfies Record<LogLevel, string>;

/** Логгер пишет в stderr, чтобы stdout оставался машиночитаемым. */
export function createConsoleLogger(minLevel: LogLevel = 'info'): Logger {
  return {
    log(level, message, details) {
      if (ORDER[level] < ORDER[minLevel]) return;

      const line = `${PREFIX[level]} ${message}`;
      if (details === undefined) process.stderr.write(`${line}\n`);
      else process.stderr.write(`${line} ${JSON.stringify(details)}\n`);
    },
  };
}

export const silentLogger: Logger = {
  log() {
    // Тесты не должны шуметь в выводе.
  },
};
