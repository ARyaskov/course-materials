import { ArgumentsHost, Catch, ExceptionFilter, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type { Request, Response } from 'express';

/**
 * Narrow filter for Prisma errors, registered *before* the catch-all
 * HttpExceptionFilter so each filter owns a clear slice of the error space.
 *
 * Codes with clean HTTP semantics are translated; anything else becomes a
 * generic 500 with the driver message kept in the logs rather than the body.
 */
@Catch(Prisma.PrismaClientKnownRequestError)
export class PrismaExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(PrismaExceptionFilter.name);

  catch(exception: Prisma.PrismaClientKnownRequestError, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const req = ctx.getRequest<Request>();
    const res = ctx.getResponse<Response>();
    const requestId = (req.headers['x-request-id'] as string | undefined) ?? 'unknown';

    const mapped = mapPrismaError(exception);
    this.logger.log({
      requestId,
      kind: 'prisma',
      prismaCode: exception.code,
      code: mapped.code,
    });
    if (mapped.status >= 500) {
      this.logger.error({ requestId, prismaCode: exception.code }, exception.message);
    }

    res
      .status(mapped.status)
      .json({ error: { code: mapped.code, message: mapped.message, requestId } });
  }
}

function mapPrismaError(e: Prisma.PrismaClientKnownRequestError): {
  status: number;
  code: string;
  message: string;
} {
  switch (e.code) {
    case 'P2002': // unique constraint violation
      return {
        status: 409,
        code: 'UNIQUE_CONSTRAINT_VIOLATION',
        message: 'Resource already exists',
      };
    case 'P2025': // record required but not found (update/delete)
      return { status: 404, code: 'NOT_FOUND', message: 'Resource not found' };
    case 'P2003': // foreign key constraint failed
      return {
        status: 409,
        code: 'FOREIGN_KEY_VIOLATION',
        message: 'Related resource constraint failed',
      };
    default:
      return { status: 500, code: 'DATABASE_ERROR', message: 'Database error' };
  }
}
