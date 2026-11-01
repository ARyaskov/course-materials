import { Injectable } from '@nestjs/common';
import type { Lesson as PrismaLesson } from '@prisma/client';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { asCourseId, asLessonId } from '../../common/types/id';
import type { Lesson } from './domain/lesson';

export interface CreateLessonData {
  courseId: string;
  title: string;
  content: string;
  position: number;
}

export interface UpdateLessonData {
  title?: string;
  content?: string;
  position?: number;
}

@Injectable()
export class LessonsRepository {
  constructor(private readonly prisma: PrismaService) {}

  async listByCourse(courseId: string): Promise<Lesson[]> {
    const rows = await this.prisma.lesson.findMany({
      where: { courseId },
      orderBy: { position: 'asc' },
    });
    return rows.map(toDomain);
  }

  async findInCourse(courseId: string, lessonId: string): Promise<Lesson | null> {
    const row = await this.prisma.lesson.findFirst({ where: { id: lessonId, courseId } });
    return row ? toDomain(row) : null;
  }

  async create(data: CreateLessonData): Promise<Lesson> {
    const row = await this.prisma.lesson.create({ data });
    return toDomain(row);
  }

  async update(lessonId: string, patch: UpdateLessonData): Promise<Lesson> {
    const row = await this.prisma.lesson.update({ where: { id: lessonId }, data: patch });
    return toDomain(row);
  }

  async delete(lessonId: string): Promise<void> {
    await this.prisma.lesson.delete({ where: { id: lessonId } });
  }

  /** Highest position currently used in a course, or 0 when it has no lessons. */
  async lastPosition(courseId: string): Promise<number> {
    const last = await this.prisma.lesson.findFirst({
      where: { courseId },
      orderBy: { position: 'desc' },
      select: { position: true },
    });
    return last?.position ?? 0;
  }
}

function toDomain(row: PrismaLesson): Lesson {
  return {
    id: asLessonId(row.id),
    courseId: asCourseId(row.courseId),
    title: row.title,
    content: row.content,
    position: row.position,
    createdAt: row.createdAt,
  };
}
