import { delay } from './delay.ts';
import { toError } from './errors.ts';

export interface RetryOptions {
  readonly attempts?: number;
  readonly delayMs?: number;
  readonly onRetry?: (attempt: number, error: Error) => void;
  readonly shouldRetry?: (error: Error) => boolean;
  readonly signal?: AbortSignal;
}

export async function retry<T>(
  operation: () => Promise<T>,
  options: RetryOptions = {},
): Promise<T> {
  const attempts = Math.max(options.attempts ?? 3, 1);
  const delayMs = options.delayMs ?? 200;
  let lastError: Error | undefined;

  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await operation();
    } catch (caught) {
      const error = toError(caught);
      lastError = error;

      if (options.shouldRetry !== undefined && !options.shouldRetry(error)) break;
      options.onRetry?.(attempt, error);

      if (attempt < attempts) {
        await delay(delayMs * attempt, options.signal);
      }
    }
  }

  throw lastError ?? new Error('retry: операция не выполнена');
}
