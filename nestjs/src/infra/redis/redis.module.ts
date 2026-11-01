import { Global, Logger, Module, OnApplicationShutdown } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ModuleRef } from '@nestjs/core';
import Redis from 'ioredis';
import { REDIS_CLIENT } from './redis.constants';
import { CacheService } from './cache.service';

/**
 * Global Redis module: one client, injected anywhere via `@Inject(REDIS_CLIENT)`.
 *
 * The client is deliberately configured to fail fast rather than to queue
 * commands forever when Redis is down — the cache is a soft dependency, and
 * callers fall back to PostgreSQL (see CacheService).
 */
@Global()
@Module({
  providers: [
    {
      provide: REDIS_CLIENT,
      inject: [ConfigService],
      useFactory: (config: ConfigService): Redis => {
        const logger = new Logger('RedisClient');
        const url = config.get<string>('redis.url') ?? 'redis://localhost:6379';

        const client = new Redis(url, {
          maxRetriesPerRequest: 2,
          connectTimeout: 5000,
          // Without this a command issued while disconnected waits indefinitely;
          // we would rather get an error and read through to the database.
          enableOfflineQueue: false,
          retryStrategy: (times) => Math.min(times * 200, 5000),
        });

        // An unhandled 'error' event on the client would crash the process, so
        // subscribing is not optional.
        client.on('error', (err: Error) => logger.warn(`Redis error: ${err.message}`));
        client.on('ready', () => logger.log('Redis ready'));
        client.on('reconnecting', () => logger.warn('Redis reconnecting'));

        return client;
      },
    },
    CacheService,
  ],
  exports: [REDIS_CLIENT, CacheService],
})
export class RedisModule implements OnApplicationShutdown {
  constructor(private readonly moduleRef: ModuleRef) {}

  async onApplicationShutdown(): Promise<void> {
    const client = this.moduleRef.get<Redis>(REDIS_CLIENT, { strict: false });
    // `quit` waits for in-flight commands; `disconnect` is the fallback when the
    // connection is already broken and QUIT would hang.
    try {
      await client.quit();
    } catch {
      client.disconnect();
    }
  }
}
