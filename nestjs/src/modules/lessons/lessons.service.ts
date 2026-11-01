import { Injectable } from '@nestjs/common';
import { LessonsRepository } from './lessons.repository';
import { CoursesService } from '../courses/courses.service';
import { CacheService } from '../../infra/redis/cache.service';
import { cacheKeys, cacheTtl } from '../../infra/redis/cache-keys';
import { DomainException } from '../../common/errors/domain-error';
import { asUserId } from '../../common/types/id';
import { toLessonResponse, type LessonResponse } from './dto/lesson.response';
import type { Lesson } from './domain/lesson';
import type { AuthUser } from '../auth/auth-user';
import type { CreateLessonRequest } from './dto/create-lesson.request';
import type { UpdateLessonRequest } from './dto/update-lesson.request';

@Injectable()
export class LessonsService {
  constructor(
    private readonly repo: LessonsRepository,
    private readonly courses: CoursesService,
    private readonly cache: CacheService,
  ) {}

  async list(courseId: string): Promise<LessonResponse[]> {
    await this.courses.getOrThrow(courseId);
    // Flat DTOs in the cache, not domain entities — JSON would turn the `Date`
    // fields of a `Lesson` into strings on the way back.
    return this.cache.wrap(cacheKeys.lessonsOfCourse(courseId), cacheTtl.lessons, async () => {
      const lessons = await this.repo.listByCourse(courseId);
      return lessons.map(toLessonResponse);
    });
  }

  async getOne(courseId: string, lessonId: string): Promise<LessonResponse> {
    return toLessonResponse(await this.getInCourseOrThrow(courseId, lessonId));
  }

  async create(
    user: AuthUser,
    courseId: string,
    body: CreateLessonRequest,
  ): Promise<LessonResponse> {
    await this.assertCanEditCourse(courseId, user);
    const position = body.position ?? (await this.repo.lastPosition(courseId)) + 1;
    const lesson = await this.repo.create({
      courseId,
      title: body.title,
      content: body.content ?? '',
      position,
    });
    await this.invalidate(courseId);
    return toLessonResponse(lesson);
  }

  async update(
    user: AuthUser,
    courseId: string,
    lessonId: string,
    body: UpdateLessonRequest,
  ): Promise<LessonResponse> {
    await this.assertCanEditCourse(courseId, user);
    await this.getInCourseOrThrow(courseId, lessonId);
    const lesson = await this.repo.update(lessonId, {
      ...(body.title !== undefined ? { title: body.title } : {}),
      ...(body.content !== undefined ? { content: body.content } : {}),
      ...(body.position !== undefined ? { position: body.position } : {}),
    });
    await this.invalidate(courseId);
    return toLessonResponse(lesson);
  }

  async remove(user: AuthUser, courseId: string, lessonId: string): Promise<void> {
    await this.assertCanEditCourse(courseId, user);
    await this.getInCourseOrThrow(courseId, lessonId);
    await this.repo.delete(lessonId);
    await this.invalidate(courseId);
  }

  private async getInCourseOrThrow(courseId: string, lessonId: string): Promise<Lesson> {
    const lesson = await this.repo.findInCourse(courseId, lessonId);
    if (!lesson) throw new DomainException({ code: 'LESSON_NOT_FOUND', lessonId });
    return lesson;
  }

  /** Editing lessons is an ownership question about their course. */
  private async assertCanEditCourse(courseId: string, user: AuthUser): Promise<void> {
    const course = await this.courses.getOrThrow(courseId);
    if (user.role !== 'admin' && course.ownerId !== asUserId(user.userId)) {
      throw new DomainException({ code: 'NOT_OWNER', resourceId: courseId });
    }
  }

  private async invalidate(courseId: string): Promise<void> {
    await this.cache.invalidate(cacheKeys.lessonsOfCourse(courseId));
  }
}
