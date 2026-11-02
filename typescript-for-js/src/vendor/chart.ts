export interface MiniChartSeries {
  readonly label: string;
  readonly values: readonly number[];
}

/** Форма внешней библиотеки, у которой нет собственных типов. */
export interface MiniChartApi {
  readonly version: string;
  render(series: MiniChartSeries, width: number): string;
}

const BLOCKS = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'] as const;

/**
 * Библиотека MiniChart подключается на странице отдельным скриптом и типов
 * не поставляет. Вместо any здесь стоит проверка формы: если объект окажется
 * не тем, что мы ожидали, код честно уйдёт на собственную реализацию.
 */
export function isMiniChart(value: unknown): value is MiniChartApi {
  if (typeof value !== 'object' || value === null) return false;

  const candidate = value as Partial<MiniChartApi>;
  return typeof candidate.version === 'string' && typeof candidate.render === 'function';
}

export function loadMiniChart(): MiniChartApi | null {
  const external: unknown = globalThis.MiniChart;
  return isMiniChart(external) ? external : null;
}

/** Собственная реализация: работает и без внешней библиотеки. */
export function sparkline(values: readonly number[], width = 24): string {
  if (values.length === 0) return '';

  const points = values.slice(-width);
  const max = Math.max(...points);
  const min = Math.min(...points);
  const span = max - min;

  return points
    .map((value) => {
      const level = span === 0 ? 0 : Math.round(((value - min) / span) * (BLOCKS.length - 1));
      return BLOCKS[level] ?? BLOCKS[0];
    })
    .join('');
}

/** Точка входа для остального кода: внешняя библиотека — деталь реализации. */
export function renderSeries(series: MiniChartSeries, width = 24): string {
  const external = loadMiniChart();
  if (external !== null) return external.render(series, width);

  return `${series.label}: ${sparkline(series.values, width)}`;
}
