import type { JsonValue } from '#lib/json.ts';
import { stringifyJson } from '#lib/json.ts';

export function printJson(value: JsonValue, write: (text: string) => void): void {
  write(`${stringifyJson(value, true)}\n`);
}

export function errorJson(message: string, details?: readonly string[]): JsonValue {
  return details === undefined ? { error: message } : { error: message, details: [...details] };
}
