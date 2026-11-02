import type { MiniChartApi } from '../src/vendor/chart.ts';

/**
 * Описание внешнего кода, который попадает в проект не через import,
 * а через глобальную область: подключённый на странице виджет метрик.
 *
 * Здесь только форма — проверка в рантайме живёт в src/vendor/chart.ts.
 */
declare global {
  var MiniChart: MiniChartApi | undefined;
}

export {};
