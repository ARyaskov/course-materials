/** Приводит внешнее значение к числу; для мусора возвращает null, а не NaN. */
export function toFiniteNumber(value: unknown): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;

  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed === '') return null;
    const parsed = Number(trimmed);
    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

export function toPositiveInt(value: unknown): number | null {
  const parsed = toFiniteNumber(value);
  if (parsed === null || !Number.isInteger(parsed) || parsed <= 0) return null;
  return parsed;
}

export function clamp(value: number, min: number, max: number): number {
  if (min > max) throw new RangeError(`Пустой диапазон: [${min}, ${max}]`);
  return Math.min(Math.max(value, min), max);
}

export function average(values: readonly number[]): number | null {
  if (values.length === 0) return null;
  const sum = values.reduce((accumulator, value) => accumulator + value, 0);
  return sum / values.length;
}

/** Перцентиль по методу ближайшего ранга: p в диапазоне 0..1. */
export function percentile(values: readonly number[], p: number): number | null {
  if (values.length === 0) return null;

  const sorted = values.toSorted((a, b) => a - b);
  const index = clamp(Math.ceil(p * sorted.length) - 1, 0, sorted.length - 1);

  return sorted[index] ?? null;
}

export function ratio(part: number, total: number): number {
  return total === 0 ? 0 : part / total;
}
