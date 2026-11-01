import { Injectable, Logger, OnApplicationShutdown, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

/**
 * Prisma client wired into Nest's lifecycle.
 *
 * Connection is attempted on init but failures are logged rather than fatal, so
 * the process still boots (e.g. `/health` stays up) when the database isn't
 * running yet. Endpoints that hit the DB will surface a clear error until
 * `docker compose up -d` + `pnpm prisma:migrate` have been run.
 */
@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnApplicationShutdown
{
  private readonly logger = new Logger(PrismaService.name);

  async onModuleInit(): Promise<void> {
    try {
      await this.$connect();
      this.logger.log('Connected to the database');
    } catch (err) {
      this.logger.warn(
        `Database connection failed at startup: ${(err as Error).message}. ` +
          'Start Postgres (docker compose up -d) and run migrations; the API is up in the meantime.',
      );
    }
  }

  async onApplicationShutdown(): Promise<void> {
    await this.$disconnect();
  }
}
