import { Injectable } from '@nestjs/common';
import { UsersRepository } from './users.repository';
import { DomainException } from '../../common/errors/domain-error';
import { hashPassword } from '../../common/security/password-hasher';
import type { User, UserRole, UserWithCredentials } from './domain/user';
import type { RegisterUserRequest } from './dto/register-user.request';

@Injectable()
export class UsersService {
  constructor(private readonly repo: UsersRepository) {}

  async register(input: RegisterUserRequest): Promise<User> {
    const existing = await this.repo.findByEmail(input.email);
    if (existing) {
      throw new DomainException({ code: 'EMAIL_ALREADY_TAKEN', email: input.email });
    }

    const passwordHash = await hashPassword(input.password);
    return this.repo.create({
      email: input.email,
      displayName: input.displayName,
      passwordHash,
      // Everyone starts as a student; becoming an instructor is an explicit,
      // admin-approved step (see `promote`).
      role: 'student',
    });
  }

  findById(id: string): Promise<User | null> {
    return this.repo.findById(id);
  }

  async getByIdOrThrow(id: string): Promise<User> {
    const user = await this.findById(id);
    if (!user) throw new DomainException({ code: 'USER_NOT_FOUND', userId: id });
    return user;
  }

  findByEmailWithCredentials(email: string): Promise<UserWithCredentials | null> {
    return this.repo.findByEmailWithCredentials(email);
  }

  /** Grants a role. Admin-only at the controller; the bootstrap admin is seeded. */
  async promote(userId: string, role: UserRole): Promise<User> {
    await this.getByIdOrThrow(userId);
    return this.repo.updateRole(userId, role);
  }
}
