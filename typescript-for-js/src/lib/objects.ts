/** Типобезопасные обёртки над Object.*: сохраняют связь ключа и значения. */
export function objectKeys<T extends object>(source: T): readonly (keyof T & string)[] {
  return Object.keys(source) as (keyof T & string)[];
}

export function objectEntries<T extends object>(
  source: T,
): readonly { [K in keyof T]: readonly [K, T[K]] }[keyof T][] {
  return Object.entries(source) as unknown as { [K in keyof T]: readonly [K, T[K]] }[keyof T][];
}

/** Достаёт значение по ключу, известному только в рантайме. */
export function getProperty<T extends object, K extends keyof T>(source: T, key: K): T[K] {
  return source[key];
}

export function pick<T extends object, K extends keyof T>(source: T, keys: readonly K[]): Pick<T, K> {
  const result = {} as Pick<T, K>;
  for (const key of keys) {
    if (key in source) result[key] = source[key];
  }
  return result;
}

export function omit<T extends object, K extends keyof T>(
  source: T,
  keys: readonly K[],
): Omit<T, K> {
  const excluded = new Set<PropertyKey>(keys);
  const result: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(source)) {
    if (!excluded.has(key)) result[key] = value;
  }

  return result as Omit<T, K>;
}

/** Мелкое сравнение объектов: достаточно для сравнения состояний UI. */
export function shallowEqual<T extends object>(left: T, right: T): boolean {
  if (left === right) return true;

  const leftKeys = Object.keys(left);
  if (leftKeys.length !== Object.keys(right).length) return false;

  return leftKeys.every(
    (key) =>
      Object.hasOwn(right, key) &&
      (left as Record<string, unknown>)[key] === (right as Record<string, unknown>)[key],
  );
}
