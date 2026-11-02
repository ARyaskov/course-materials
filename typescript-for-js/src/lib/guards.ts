export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function isString(value: unknown): value is string {
  return typeof value === 'string';
}

export function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0;
}

export function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

export function isBoolean(value: unknown): value is boolean {
  return typeof value === 'boolean';
}

export function isArrayOf<T>(value: unknown, item: (v: unknown) => v is T): value is readonly T[] {
  return Array.isArray(value) && value.every(item);
}

export function isNullable<T>(value: unknown, inner: (v: unknown) => v is T): value is T | null {
  return value === null || inner(value);
}

export function isNotNull<T>(value: T | null): value is T {
  return value !== null;
}

export function isDefined<T>(value: T | undefined): value is T {
  return value !== undefined;
}

export function hasKey<K extends string>(value: unknown, key: K): value is Record<K, unknown> {
  return isRecord(value) && key in value;
}
