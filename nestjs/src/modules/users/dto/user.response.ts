import type { User } from '../domain/user';

export interface UserResponse {
  readonly id: string;
  readonly email: string;
  readonly displayName: string;
  readonly role: 'student' | 'instructor' | 'admin';
  readonly createdAt: string;
}

export function toUserResponse(u: User): UserResponse {
  return {
    id: u.id,
    email: u.email,
    displayName: u.displayName,
    role: u.role,
    createdAt: u.createdAt.toISOString(),
  };
}
