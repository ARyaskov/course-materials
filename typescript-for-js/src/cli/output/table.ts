export interface Column<T> {
  readonly title: string;
  /** Как получить текст ячейки из строки данных. */
  readonly value: (row: T) => string;
}

/** Колонка по имени поля: опечатка в ключе — ошибка компиляции. */
export function column<T>(title: string, key: keyof T & string): Column<T> {
  return { title, value: (row) => String(row[key]) };
}

function widthOf(text: string): number {
  return [...text].length;
}

function pad(text: string, width: number): string {
  return text + ' '.repeat(Math.max(width - widthOf(text), 0));
}

/** Печать таблицы для терминала: колонки выравниваются по самой длинной ячейке. */
export function renderTable<T>(rows: readonly T[], columns: readonly Column<T>[]): string {
  if (rows.length === 0) return 'Нет данных';

  const cells = rows.map((row) => columns.map((currentColumn) => currentColumn.value(row)));

  const widths = columns.map((currentColumn, index) =>
    cells.reduce((width, row) => Math.max(width, widthOf(row[index] ?? '')), widthOf(currentColumn.title)),
  );

  const line = (values: readonly string[]): string =>
    values.map((value, index) => pad(value, widths[index] ?? 0)).join('  ');

  const header = line(columns.map((currentColumn) => currentColumn.title));
  const separator = widths.map((width) => '─'.repeat(width)).join('  ');

  return [header, separator, ...cells.map(line)].join('\n');
}
