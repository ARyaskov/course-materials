export function first<T>(items: readonly T[]): T | undefined {
  return items[0];
}

export function last<T>(items: readonly T[]): T | undefined {
  return items.at(-1);
}

export function byId<T extends { readonly id: string }>(
  items: readonly T[],
  id: string,
): T | undefined {
  return items.find((item) => item.id === id);
}

export function groupBy<T, K extends string>(
  items: readonly T[],
  keyOf: (item: T) => K,
): Readonly<Partial<Record<K, readonly T[]>>> {
  const result: Partial<Record<K, T[]>> = {};

  for (const item of items) {
    const key = keyOf(item);
    const bucket = result[key];
    if (bucket === undefined) result[key] = [item];
    else bucket.push(item);
  }

  return result;
}

export function countBy<T, K extends string>(
  items: readonly T[],
  keyOf: (item: T) => K,
): Readonly<Partial<Record<K, number>>> {
  const result: Partial<Record<K, number>> = {};

  for (const item of items) {
    const key = keyOf(item);
    result[key] = (result[key] ?? 0) + 1;
  }

  return result;
}

export function mapNotNull<T, R>(
  items: readonly T[],
  transform: (item: T) => R | null,
): readonly R[] {
  const result: R[] = [];

  for (const item of items) {
    const value = transform(item);
    if (value !== null) result.push(value);
  }

  return result;
}

export function sortBy<T, K extends string | number>(
  items: readonly T[],
  keyOf: (item: T) => K,
  direction: 'asc' | 'desc' = 'asc',
): readonly T[] {
  const sign = direction === 'asc' ? 1 : -1;

  return items.toSorted((a, b) => {
    const left = keyOf(a);
    const right = keyOf(b);
    if (left === right) return 0;
    return (left < right ? -1 : 1) * sign;
  });
}

export function pluck<T, K extends keyof T>(items: readonly T[], key: K): readonly T[K][] {
  return items.map((item) => item[key]);
}

export function unique<T>(items: readonly T[]): readonly T[] {
  return [...new Set(items)];
}
