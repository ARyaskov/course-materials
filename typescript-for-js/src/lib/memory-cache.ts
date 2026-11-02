import type { Cache } from '#services/ports.ts';

import type { Clock } from './date.ts';
import { systemClock } from './date.ts';

interface Entry<T> {
  readonly value: T;
  readonly expiresAt: number;
}

/** Кеш в памяти с временем жизни записи; обобщён по типу значения. */
export class MemoryCache<T> implements Cache<T> {
  readonly #entries = new Map<string, Entry<T>>();
  readonly #ttlMs: number;
  readonly #clock: Clock;

  constructor(ttlMs: number, clock: Clock = systemClock) {
    if (ttlMs <= 0) throw new RangeError('TTL должен быть положительным');
    this.#ttlMs = ttlMs;
    this.#clock = clock;
  }

  get size(): number {
    return this.#entries.size;
  }

  get(key: string): T | null {
    const entry = this.#entries.get(key);
    if (entry === undefined) return null;

    if (entry.expiresAt <= this.#clock.now().getTime()) {
      this.#entries.delete(key);
      return null;
    }

    return entry.value;
  }

  set(key: string, value: T): void {
    this.#entries.set(key, { value, expiresAt: this.#clock.now().getTime() + this.#ttlMs });
  }

  delete(key: string): void {
    this.#entries.delete(key);
  }

  clear(): void {
    this.#entries.clear();
  }
}
