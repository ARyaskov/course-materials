import type { UserId } from '../../../common/types/id';

export type UserRole = 'student' | 'instructor' | 'admin';

export interface User {
  readonly id: UserId;
  readonly email: string;
  readonly displayName: string;
  readonly role: UserRole;
  readonly createdAt: Date;
}

/** Internal shape that also carries the password hash — never returned to clients. */
export interface UserWithCredentials extends User {
  readonly passwordHash: string;
}
