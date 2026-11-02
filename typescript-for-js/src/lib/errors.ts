export class ShipyardError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = new.target.name;
  }
}

export class HttpError extends ShipyardError {
  readonly status: number;
  readonly url: string;

  constructor(status: number, url: string) {
    super(`HTTP ${status} для ${url}`);
    this.status = status;
    this.url = url;
  }
}

export class ValidationError extends ShipyardError {
  readonly issues: readonly string[];

  constructor(issues: readonly string[]) {
    super(`Данные не прошли проверку (${issues.length})`);
    this.issues = issues;
  }
}

export class ConfigError extends ShipyardError {}

export function toError(value: unknown): Error {
  if (value instanceof Error) return value;
  if (typeof value === 'string') return new Error(value);
  return new Error(`Неизвестная ошибка: ${JSON.stringify(value)}`, { cause: value });
}

export function describeError(value: unknown, depth = 0): string {
  const error = toError(value);
  const own = `${error.name}: ${error.message}`;
  if (error.cause === undefined || depth >= 3) return own;
  return `${own}\n  причина: ${describeError(error.cause, depth + 1)}`;
}

export function isAbortError(value: unknown): boolean {
  return value instanceof DOMException && value.name === 'AbortError';
}

export function isTimeoutError(value: unknown): boolean {
  return value instanceof DOMException && value.name === 'TimeoutError';
}
