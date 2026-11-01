import { Inject, Injectable, Logger } from '@nestjs/common';
import type Redis from 'ioredis';
import { REDIS_CLIENT } from './redis.constants';
import { cacheTtl } from './cache-keys';

/** Marker distinguishing "cached absence" from "nothing cached under this key". */
const NOT_FOUND_MARKER = '__not_found__';

/**
 * Cache-aside helper: ask Redis, fall back to the loader on a miss, write the
 * result back with a TTL.
 *
 * Every Redis call is wrapped: when the cache is unavailable the request still
 * succeeds against PostgreSQL, just without the speed-up. A cache outage must
 * not become an API outage.
 */
@Injectable()
export class CacheService {
  private readonly logger = new Logger(CacheService.name);

  constructor(@Inject(REDIS_CLIENT) private readonly redis: Redis) {}

  /**
   * Reads through the cache. `loader` runs only on a miss.
   *
   * The stored TTL is jittered by up to 10% so keys created in the same second
   * don't all expire in the same second — a hundred parallel misses hitting the
   * database at once is the stampede this avoids.
   */
  async wrap<T>(key: string, ttlSeconds: number, loader: () => Promise<T>): Promise<T> {
    const cached = await this.get(key);
    if (cached !== null) {
      return JSON.parse(cached) as T;
    }

    const value = await loader();
    await this.set(key, JSON.stringify(value), ttlSeconds);
    return value;
  }

  /**
   * Same as `wrap`, but for lookups that legitimately return nothing. The empty
   * result is cached briefly so a scan of random ids can't bypass the cache
   * entirely and hammer the database.
   */
  async wrapNullable<T>(
    key: string,
    ttlSeconds: number,
    loader: () => Promise<T | null>,
  ): Promise<T | null> {
    const cached = await this.get(key);
    if (cached === NOT_FOUND_MARKER) return null;
    if (cached !== null) return JSON.parse(cached) as T;

    const value = await loader();
    if (value === null) {
      await this.set(key, NOT_FOUND_MARKER, cacheTtl.notFound);
      return null;
    }

    await this.set(key, JSON.stringify(value), ttlSeconds);
    return value;
  }

  /** Drops individual keys. Safe to call with keys that don't exist. */
  async invalidate(...keys: string[]): Promise<void> {
    if (keys.length === 0) return;
    try {
      // UNLINK frees memory in a background thread instead of blocking Redis.
      await this.redis.unlink(...keys);
    } catch (err) {
      this.logger.warn(`Cache invalidate failed: ${(err as Error).message}`);
    }
  }

  /** Drops every key matching a pattern, using SCAN so Redis is never blocked. */
  async invalidatePattern(pattern: string): Promise<void> {
    try {
      const stream = this.redis.scanStream({ match: pattern, count: 100 });
      for await (const keys of stream as AsyncIterable<string[]>) {
        if (keys.length > 0) {
          await this.redis.unlink(...keys);
        }
      }
    } catch (err) {
      this.logger.warn(`Cache pattern invalidate failed: ${(err as Error).message}`);
    }
  }

  private async get(key: string): Promise<string | null> {
    try {
      return await this.redis.get(key);
    } catch (err) {
      this.logger.warn(`Cache read failed for ${key}: ${(err as Error).message}`);
      return null;
    }
  }

  private async set(key: string, value: string, ttlSeconds: number): Promise<void> {
    try {
      await this.redis.set(key, value, 'EX', withJitter(ttlSeconds));
    } catch (err) {
      this.logger.warn(`Cache write failed for ${key}: ${(err as Error).message}`);
    }
  }
}

function withJitter(ttlSeconds: number): number {
  return ttlSeconds + Math.floor(Math.random() * Math.ceil(ttlSeconds * 0.1));
}
