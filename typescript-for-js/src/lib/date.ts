import type { IsoDateTime } from '#domain/release.ts';

/** Часы — единственное место, откуда код узнаёт текущее время. */
export interface Clock {
  now(): Date;
}

export const systemClock: Clock = {
  now: () => new Date(),
};

/** Фиксированные часы для тестов: время не «плывёт» между проверками. */
export function fixedClock(iso: IsoDateTime): Clock {
  const fixed = new Date(iso);
  return { now: () => new Date(fixed) };
}

export function toIso(date: Date): IsoDateTime {
  return date.toISOString();
}

export function parseIso(value: string): Date | null {
  const time = Date.parse(value);
  return Number.isFinite(time) ? new Date(time) : null;
}

export function isValidIso(value: string): boolean {
  return parseIso(value) !== null;
}

export function diffMs(from: IsoDateTime, to: IsoDateTime): number | null {
  const start = parseIso(from);
  const end = parseIso(to);
  if (start === null || end === null) return null;
  return end.getTime() - start.getTime();
}

export function agoMs(iso: IsoDateTime, clock: Clock = systemClock): number | null {
  const moment = parseIso(iso);
  if (moment === null) return null;
  return clock.now().getTime() - moment.getTime();
}
