import { Injectable } from '@nestjs/common';
import type { User as PrismaUser } from '@prisma/client';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { asUserId } from '../../common/types/id';
import type { User, UserRole, UserWithCredentials } from './domain/user';

export interface CreateUserData {
  email: string;
  displayName: string;
  passwordHash: string;
  role: UserRole;
}

/**
 * Persistence for users. The service above it never sees a Prisma row: the
 * mapping to the domain type happens here, in one place.
 */
@Injectable()
export class UsersRepository {
  constructor(private readonly prisma: PrismaService) {}

  async findById(id: string): Promise<User | null> {
    const row = await this.prisma.user.findUnique({ where: { id } });
    return row ? toDomain(row) : null;
  }

  async findByEmail(email: string): Promise<User | null> {
    const row = await this.prisma.user.findUnique({ where: { email } });
    return row ? toDomain(row) : null;
  }

  async findByEmailWithCredentials(email: string): Promise<UserWithCredentials | null> {
    const row = await this.prisma.user.findUnique({ where: { email } });
    return row ? toDomainWithCredentials(row) : null;
  }

  async create(data: CreateUserData): Promise<User> {
    const row = await this.prisma.user.create({ data });
    return toDomain(row);
  }

  async updateRole(id: string, role: UserRole): Promise<User> {
    const row = await this.prisma.user.update({ where: { id }, data: { role } });
    return toDomain(row);
  }
}

function toDomain(row: PrismaUser): User {
  return {
    id: asUserId(row.id),
    email: row.email,
    displayName: row.displayName,
    role: row.role,
    createdAt: row.createdAt,
  };
}

function toDomainWithCredentials(row: PrismaUser): UserWithCredentials {
  return { ...toDomain(row), passwordHash: row.passwordHash };
}
