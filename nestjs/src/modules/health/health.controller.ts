import { Controller, Get, Inject } from '@nestjs/common';
import { ApiOkResponse, ApiTags } from '@nestjs/swagger';
import type Redis from 'ioredis';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { REDIS_CLIENT } from '../../infra/redis/redis.constants';

interface HealthResponse {
  readonly status: 'ok';
  readonly uptimeSeconds: number;
  readonly startedAt: string;
}

interface ReadinessResponse {
  readonly status: 'ok' | 'degraded';
  readonly checks: { database: 'up' | 'down'; redis: 'up' | 'down' };
}

const startedAt = new Date();
const REDIS_PING_TIMEOUT_MS = 1000;

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
  ) {}

  /** Liveness — is the process up? Never touches external systems. */
  @Get()
  @ApiOkResponse({ description: 'Process is alive' })
  check(): HealthResponse {
    return {
      status: 'ok',
      uptimeSeconds: Math.floor(process.uptime()),
      startedAt: startedAt.toISOString(),
    };
  }

  /**
   * Readiness — can we serve traffic? Probes both dependencies.
   *
   * The probe is read by the orchestrator, so it stays cheap and bounded: a
   * `SELECT 1` and a `PING`, each with a short timeout.
   */
  @Get('ready')
  @ApiOkResponse({ description: 'Dependency readiness' })
  async ready(): Promise<ReadinessResponse> {
    const [database, redis] = await Promise.all([this.checkDatabase(), this.checkRedis()]);
    return {
      status: database === 'up' && redis === 'up' ? 'ok' : 'degraded',
      checks: { database, redis },
    };
  }

  private async checkDatabase(): Promise<'up' | 'down'> {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
      return 'up';
    } catch {
      return 'down';
    }
  }

  private async checkRedis(): Promise<'up' | 'down'> {
    try {
      const pong = await withTimeout(this.redis.ping(), REDIS_PING_TIMEOUT_MS);
      return pong === 'PONG' ? 'up' : 'down';
    } catch {
      return 'down';
    }
  }
}

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_resolve, reject) =>
      setTimeout(() => reject(new Error('timeout')), ms).unref(),
    ),
  ]);
}
