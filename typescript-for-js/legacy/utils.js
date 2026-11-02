// Набор утилит из старой версии проекта. Каждая функция здесь принимает
// «что угодно» и возвращает «что-нибудь» — типизированные версии живут
// в src/lib/ (format.ts, number.ts, collections.ts, objects.ts).

export function formatDuration(ms) {
  if (!ms) return '—';
  if (ms < 1000) return Math.round(ms) + ' мс';

  const seconds = Math.round(ms / 1000);
  const minutes = Math.floor(seconds / 60);

  return minutes ? minutes + ' мин ' + (seconds % 60) + ' с' : seconds + ' с';
}

export function groupBy(items, key) {
  const result = {};

  for (const item of items) {
    const value = item[key];
    result[value] = result[value] || [];
    result[value].push(item);
  }

  return result;
}

export function pluck(items, key) {
  return items.map((item) => item[key]);
}

export function unique(items) {
  return items.filter((item, index) => items.indexOf(item) === index);
}

export function average(values) {
  if (!values.length) return 0;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

export function pick(source, keys) {
  const result = {};

  for (const key of keys) {
    result[key] = source[key];
  }

  return result;
}
