import {
  CallHandler,
  ExecutionContext,
  Inject,
  Injectable,
  Logger,
  NestInterceptor,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Request } from 'express';
import type Redis from 'ioredis';
import { catchError, from, switchMap, throwError, type Observable } from 'rxjs';
import { DomainException } from '../../common/errors/domain-error';
import { REDIS_CLIENT } from '../../infra/redis/redis.constants';
import type { SecurityConfig } from '../../config/security.config';

interface LoginIdentity {
  ip: string;
  email: string | null;
}

/**
 * Brute-force budget for the login endpoint: two fixed windows in Redis, one
 * per client IP and one per email address.
 *
 * Only *failed* attempts are counted. A guard running before the handler cannot
 * know the outcome, which is why this is an interceptor: it checks the counters
 * on the way in and increments them on the way out, but only when the attempt
 * was rejected. Counting successes too would lock out a shared office IP after
 * five ordinary logins.
 *
 * The IP window stops single-host brute-forcing; the email window stops a
 * botnet from spreading attempts on one account across many addresses.
 *
 * Redis being down must not lock everyone out, so every failure path here falls
 * open and logs.
 */
@Injectable()
export class LoginRateLimitInterceptor implements NestInterceptor {
  private readonly logger = new Logger(LoginRateLimitInterceptor.name);

  constructor(
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
    private readonly config: ConfigService,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<Request>();
    const body = request.body as { email?: unknown } | undefined;
    const identity: LoginIdentity = {
      // `request.ip` honours the trust-proxy setting configured in main.ts.
      ip: request.ip ?? 'unknown',
      email: typeof body?.email === 'string' ? body.email.trim().toLowerCase() : null,
    };

    return from(this.assertWithinLimits(identity)).pipe(
      switchMap(() => next.handle()),
      catchError((err: unknown) =>
        from(this.registerFailure(identity, err)).pipe(switchMap(() => throwError(() => err))),
      ),
    );
  }

  private async assertWithinLimits(identity: LoginIdentity): Promise<void> {
    const policy = this.policy();
    if (!policy) return;

    await this.assertKey(`rate:login:ip:${identity.ip}`, policy.perIp);
    if (identity.email) {
      await this.assertKey(`rate:login:email:${identity.email}`, policy.perEmail);
    }
  }

  private async assertKey(key: string, limit: number): Promise<void> {
    let hits: number;
    let ttl: number;

    try {
      const [rawHits, rawTtl] = await Promise.all([this.redis.get(key), this.redis.ttl(key)]);
      hits = Number(rawHits ?? 0);
      ttl = rawTtl;
    } catch (err) {
      this.logger.warn(`Login rate limiting unavailable: ${(err as Error).message}`);
      return;
    }

    if (hits >= limit) {
      this.logger.warn(`Login rate limit hit for ${key} (${hits}/${limit})`);
      throw new DomainException({
        code: 'RATE_LIMITED',
        retryAfterSeconds: ttl > 0 ? ttl : 60,
      });
    }
  }

  /** Counts the attempt only when it failed for a credential-ish reason. */
  private async registerFailure(identity: LoginIdentity, err: unknown): Promise<void> {
    const policy = this.policy();
    if (!policy || !countsAsFailedAttempt(err)) return;

    await this.increment(`rate:login:ip:${identity.ip}`, policy.perIpWindowSeconds);
    if (identity.email) {
      await this.increment(`rate:login:email:${identity.email}`, policy.perEmailWindowSeconds);
    }
  }

  private async increment(key: string, windowSeconds: number): Promise<void> {
    try {
      await this.redis
        .multi()
        .incr(key)
        // NX: set the TTL when the window opens, so repeated attempts don't keep
        // pushing the expiry forward and turn a fixed window into an endless one.
        .expire(key, windowSeconds, 'NX')
        .exec();
    } catch (err) {
      this.logger.warn(`Login rate counter update failed: ${(err as Error).message}`);
    }
  }

  private policy(): SecurityConfig['login'] | undefined {
    return this.config.get<SecurityConfig['login']>('security.login');
  }
}

function countsAsFailedAttempt(err: unknown): boolean {
  // Being blocked doesn't extend the block, and a malformed payload isn't a
  // password guess — only real credential rejections move the counter.
  return err instanceof DomainException && err.error.code === 'INVALID_CREDENTIALS';
}
