import { Injectable } from '@nestjs/common';
import { Prisma, type Course as PrismaCourse } from '@prisma/client';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { asCourseId, asUserId } from '../../common/types/id';
import type { Course, CourseStatus } from './domain/course';

export interface ListCoursesParams {
  status?: CourseStatus;
  search?: string;
  limit: number;
  offset: number;
  sortBy: 'createdAt' | 'title' | 'priceCents';
  sortOrder: 'asc' | 'desc';
}

export interface CreateCourseData {
  ownerId: string;
  title: string;
  description: string;
  priceCents: number;
}

export interface UpdateCourseData {
  title?: string;
  description?: string;
  priceCents?: number;
  status?: CourseStatus;
  publishedAt?: Date | null;
}

@Injectable()
export class CoursesRepository {
  constructor(private readonly prisma: PrismaService) {}

  async findById(id: string): Promise<Course | null> {
    const row = await this.prisma.course.findUnique({ where: { id } });
    return row ? toDomain(row) : null;
  }

  async create(data: CreateCourseData): Promise<Course> {
    const row = await this.prisma.course.create({ data });
    return toDomain(row);
  }

  async update(id: string, patch: UpdateCourseData): Promise<Course> {
    const row = await this.prisma.course.update({ where: { id }, data: patch });
    return toDomain(row);
  }

  async delete(id: string): Promise<void> {
    await this.prisma.course.delete({ where: { id } });
  }

  async list(params: ListCoursesParams): Promise<{ items: Course[]; total: number }> {
    const where: Prisma.CourseWhereInput = {
      ...(params.status ? { status: params.status } : {}),
      ...(params.search ? { title: { contains: params.search, mode: 'insensitive' } } : {}),
    };
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.course.findMany({
        where,
        skip: params.offset,
        take: params.limit,
        orderBy: { [params.sortBy]: params.sortOrder },
      }),
      this.prisma.course.count({ where }),
    ]);
    return { items: rows.map(toDomain), total };
  }
}

function toDomain(row: PrismaCourse): Course {
  return {
    id: asCourseId(row.id),
    ownerId: asUserId(row.ownerId),
    title: row.title,
    description: row.description,
    priceCents: row.priceCents,
    status: row.status,
    createdAt: row.createdAt,
    publishedAt: row.publishedAt,
  };
}
