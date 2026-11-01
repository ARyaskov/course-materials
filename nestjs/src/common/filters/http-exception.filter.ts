import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { Prisma } from '@prisma/client';
import { DomainException } from '../errors/domain-error';
import { mapDomainToHttp } from '../errors/map-domain-to-http';

/**
 * Catch-all filter producing a single, stable error envelope:
 *   { "error": { "code": "...", "message": "...", "details"?: {...}, "requestId": "..." } }
 *
 * - DomainException  -> mapped via the domain error table
 * - HttpException    -> normalized (also flattens class-validator message arrays)
 * - anything else    -> 500 INTERNAL_ERROR (details hidden from the client)
 */
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const req = ctx.getRequest<Request>();
    const res = ctx.getResponse<Response>();
    const requestId = (req.headers['x-request-id'] as string | undefined) ?? 'unknown';

    if (exception instanceof DomainException) {
      const mapped = mapDomainToHttp(exception.error);
      this.logger.log({ requestId, kind: 'domain', code: exception.error.code });
      if (exception.error.code === 'RATE_LIMITED') {
        // Clients need to know how long to back off, not just that they were blocked.
        res.setHeader('Retry-After', String(exception.error.retryAfterSeconds));
      }
      res.status(mapped.status).json({ error: { ...mapped.body, requestId } });
      return;
    }

    if (exception instanceof Prisma.PrismaClientKnownRequestError) {
      const mapped = mapPrismaError(exception);
      this.logger.log({
        requestId,
        kind: 'prisma',
        prismaCode: exception.code,
        code: mapped.code,
      });
      res
        .status(mapped.status)
        .json({ error: { code: mapped.code, message: mapped.message, requestId } });
      return;
    }

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = normalizeHttpBody(exception.getResponse(), status);
      this.logger.log({ requestId, kind: 'http', status, code: body.code });
      res.status(status).json({ error: { ...body, requestId } });
      return;
    }

    this.logger.error({ requestId, kind: 'unknown' }, (exception as Error)?.stack);
    res.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      error: { code: 'INTERNAL_ERROR', message: 'Internal server error', requestId },
    });
  }
}

function normalizeHttpBody(raw: unknown, status: number) {
  if (raw && typeof raw === 'object') {
    const obj = raw as Record<string, unknown>;
    return {
      code: typeof obj.code === 'string' ? obj.code : codeForStatus(status),
      message:
        typeof obj.message === 'string'
          ? obj.message
          : Array.isArray(obj.message)
            ? obj.message.join('; ')
            : messageForStatus(status),
      details:
        obj.details && typeof obj.details === 'object'
          ? (obj.details as Record<string, unknown>)
          : undefined,
    };
  }
  return {
    code: codeForStatus(status),
    message: typeof raw === 'string' ? raw : messageForStatus(status),
  };
}

function mapPrismaError(e: Prisma.PrismaClientKnownRequestError): {
  status: number;
  code: string;
  message: string;
} {
  switch (e.code) {
    case 'P2002':
      return {
        status: 409,
        code: 'UNIQUE_CONSTRAINT_VIOLATION',
        message: 'Resource already exists',
      };
    case 'P2025':
      return { status: 404, code: 'NOT_FOUND', message: 'Resource not found' };
    case 'P2003':
      return {
        status: 409,
        code: 'FOREIGN_KEY_VIOLATION',
        message: 'Related resource constraint failed',
      };
    default:
      return { status: 500, code: 'DATABASE_ERROR', message: 'Database error' };
  }
}

function codeForStatus(status: number): string {
  if (status === 400) return 'BAD_REQUEST';
  if (status === 401) return 'UNAUTHORIZED';
  if (status === 403) return 'FORBIDDEN';
  if (status === 404) return 'NOT_FOUND';
  if (status === 409) return 'CONFLICT';
  if (status === 429) return 'RATE_LIMITED';
  return 'ERROR';
}

function messageForStatus(status: number): string {
  if (status >= 500) return 'Internal server error';
  return 'Bad Request';
}
