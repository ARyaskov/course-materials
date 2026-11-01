import type { UserRole } from '../users/domain/user';

/** The authenticated principal attached to `request.user` by the JWT strategy. */
export interface AuthUser {
  readonly userId: string;
  readonly email: string;
  readonly role: UserRole;
}

/** Shape of the signed JWT access-token payload. */
export interface JwtPayload {
  sub: string;
  email: string;
  role: UserRole;
  type: 'access' | 'refresh';
}
