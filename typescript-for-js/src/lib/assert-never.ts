/** Проверка полноты обработки объединения: вызов допустим только там, где вариантов не осталось. */
export function assertNever(value: never, context: string): never {
  throw new Error(`${context}: необработанный вариант ${JSON.stringify(value)}`);
}
