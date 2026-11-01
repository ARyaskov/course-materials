import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { DomainException } from '../../common/errors/domain-error';
import type { UserRole } from '../users/domain/user';
import type { AuthUser } from './auth-user';
import { ROLES_KEY } from './roles.decorator';

/**
 * Checks the *role* of the caller — a property of the user, independent of any
 * particular resource. Ownership ("this course is mine") is a different
 * question and is answered inside the service, where the record is loaded
 * anyway.
 *
 * Runs after JwtAuthGuard, so `request.user` is already populated.
 */
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<UserRole[] | undefined>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!required || required.length === 0) {
      return true;
    }

    const request = context.switchToHttp().getRequest<Request & { user?: AuthUser }>();
    const user = request.user;
    if (!user) {
      throw new UnauthorizedException('Authentication is required');
    }

    if (!required.includes(user.role)) {
      // 403, not 401: the caller is authenticated, just not allowed. Authoring
      // endpoints get the specific code clients can branch on; everything else
      // falls back to the generic one.
      if (required.includes('instructor')) {
        throw new DomainException({ code: 'NOT_AN_INSTRUCTOR', userId: user.userId });
      }
      throw new ForbiddenException({
        code: 'FORBIDDEN',
        message: 'Your role does not allow this action',
      });
    }

    return true;
  }
}
