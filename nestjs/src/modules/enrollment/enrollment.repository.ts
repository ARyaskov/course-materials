import { Injectable } from '@nestjs/common';
import type { Course as PrismaCourse, Enrollment as PrismaEnrollment } from '@prisma/client';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { asCourseId, asEnrollmentId, asUserId } from '../../common/types/id';
import type { Enrollment, EnrollmentWithCourse } from './domain/enrollment';

@Injectable()
export class EnrollmentRepository {
  constructor(private readonly prisma: PrismaService) {}

  async find(userId: string, courseId: string): Promise<Enrollment | null> {
    const row = await this.prisma.enrollment.findUnique({
      where: { userId_courseId: { userId, courseId } },
    });
    return row ? toDomain(row) : null;
  }

  async create(userId: string, courseId: string): Promise<Enrollment> {
    const row = await this.prisma.enrollment.create({ data: { userId, courseId } });
    return toDomain(row);
  }

  async listByUser(userId: string): Promise<EnrollmentWithCourse[]> {
    const rows = await this.prisma.enrollment.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      // One query with a join instead of one query per enrollment.
      include: { course: true },
    });
    return rows.map((row) => ({ ...toDomain(row), course: toEnrolledCourse(row.course) }));
  }

  async delete(enrollmentId: string): Promise<void> {
    await this.prisma.enrollment.delete({ where: { id: enrollmentId } });
  }
}

function toDomain(row: PrismaEnrollment): Enrollment {
  return {
    id: asEnrollmentId(row.id),
    userId: asUserId(row.userId),
    courseId: asCourseId(row.courseId),
    createdAt: row.createdAt,
  };
}

function toEnrolledCourse(row: PrismaCourse): EnrollmentWithCourse['course'] {
  return {
    id: asCourseId(row.id),
    title: row.title,
    status: row.status,
    priceCents: row.priceCents,
  };
}
