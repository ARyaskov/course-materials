/** Доступ по индексу там, где он гарантирован логикой: понятная ошибка вместо undefined. */
export function atOrThrow<T>(items: readonly T[], index: number): T {
  const value = items[index];
  if (value === undefined) {
    throw new RangeError(`Индекс ${index} вне диапазона (длина ${items.length})`);
  }
  return value;
}

export function chunk<T>(items: readonly T[], size: number): readonly (readonly T[])[] {
  if (size < 1) throw new RangeError('Размер блока должен быть положительным');

  const result: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    result.push(items.slice(i, i + size));
  }
  return result;
}
