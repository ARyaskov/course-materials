export function formatDuration(ms: number | null): string {
  if (ms === null || !Number.isFinite(ms) || ms < 0) return '—';
  if (ms < 1000) return `${Math.round(ms)} мс`;

  const totalSeconds = Math.round(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  if (minutes === 0) return `${seconds} с`;
  if (minutes < 60) return `${minutes} мин ${seconds} с`;

  const hours = Math.floor(minutes / 60);
  return `${hours} ч ${minutes % 60} мин`;
}

export function formatPercent(value: number, fractionDigits = 1): string {
  if (!Number.isFinite(value)) return '—';
  return `${(value * 100).toFixed(fractionDigits)}%`;
}

/** Склонение существительного: 1 деплой, 2 деплоя, 5 деплоев. */
export function formatCount(count: number, forms: readonly [string, string, string]): string {
  const abs = Math.abs(count) % 100;
  const tail = abs % 10;

  const word =
    abs > 10 && abs < 20 ? forms[2] : tail > 1 && tail < 5 ? forms[1] : tail === 1 ? forms[0] : forms[2];

  return `${count} ${word}`;
}

export function formatDateTime(iso: string | null): string {
  if (iso === null) return '—';
  const parsed = Date.parse(iso);
  if (!Number.isFinite(parsed)) return iso;

  const date = new Date(parsed);
  const pad = (value: number): string => String(value).padStart(2, '0');

  return (
    `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())} ` +
    `${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}`
  );
}
