import { Injectable } from '@nestjs/common';
import { CoursesRepository } from './courses.repository';
import { CoursesCache } from './courses-cache';
import { courseEvent } from './domain/events';
import { CacheService } from '../../infra/redis/cache.service';
import { cacheKeys, cacheTtl } from '../../infra/redis/cache-keys';
import { DomainException } from '../../common/errors/domain-error';
import { asCourseId, asUserId } from '../../common/types/id';
import type { Page } from '../../common/types/page';
import type { Course } from './domain/course';
import type { AuthUser } from '../auth/auth-user';
import { toCourseResponse, type CourseResponse } from './dto/course.response';
import type { CreateCourseRequest } from './dto/create-course.request';
import type { UpdateCourseRequest } from './dto/update-course.request';
import type { ListCoursesQuery } from './dto/list-courses.query';

@Injectable()
export class CoursesService {
  constructor(
    private readonly repo: CoursesRepository,
    private readonly cache: CacheService,
    private readonly coursesCache: CoursesCache,
  ) {}

  /**
   * Read-heavy endpoint, so it goes through the cache. On a miss the loader
   * hits PostgreSQL and the result is written back with a short TTL — stale
   * lists heal on their own even if an invalidation is ever missed.
   */
  async list(q: ListCoursesQuery): Promise<Page<CourseResponse>> {
    const key = cacheKeys.courseList({
      status: q.status,
      search: q.search,
      limit: q.limit,
      offset: q.offset,
      sortBy: q.sortBy,
      sortOrder: q.sortOrder,
    });

    return this.cache.wrap(key, cacheTtl.courseList, async () => {
      const { items, total } = await this.repo.list({
        status: q.status,
        search: q.search,
        limit: q.limit,
        offset: q.offset,
        sortBy: q.sortBy,
        sortOrder: q.sortOrder,
      });
      return {
        items: items.map(toCourseResponse),
        total,
        limit: q.limit,
        offset: q.offset,
      };
    });
  }

  async getById(id: string): Promise<CourseResponse> {
    // Flat response DTOs go into the cache, never domain entities: JSON has no
    // Date, so a cached `Course` would come back with strings where the mapper
    // expects `Date` objects.
    //
    // `wrapNullable` also caches the miss briefly, so scanning random ids can't
    // walk straight past the cache into the database.
    const cached = await this.cache.wrapNullable(
      cacheKeys.course(id),
      cacheTtl.course,
      async () => {
        const course = await this.repo.findById(id);
        return course ? toCourseResponse(course) : null;
      },
    );
    if (!cached) throw new DomainException({ code: 'COURSE_NOT_FOUND', courseId: id });
    return cached;
  }

  async create(ownerId: string, body: CreateCourseRequest): Promise<CourseResponse> {
    const course = await this.repo.create({
      ownerId,
      title: body.title,
      description: body.description,
      priceCents: body.priceCents,
    });
    await this.coursesCache.onCourseChanged(
      courseEvent('course.created', course.id, course.ownerId),
    );
    return toCourseResponse(course);
  }

  async update(
    user: AuthUser,
    id: string,
    body: UpdateCourseRequest,
  ): Promise<CourseResponse> {
    await this.assertCanModify(id, user);
    const course = await this.repo.update(id, {
      ...(body.title !== undefined ? { title: body.title } : {}),
      ...(body.description !== undefined ? { description: body.description } : {}),
      ...(body.priceCents !== undefined ? { priceCents: body.priceCents } : {}),
    });
    await this.coursesCache.onCourseChanged(
      courseEvent('course.updated', course.id, course.ownerId),
    );
    return toCourseResponse(course);
  }

  async publish(user: AuthUser, id: string): Promise<CourseResponse> {
    const course = await this.assertCanModify(id, user);
    if (course.status === 'published') {
      // Not a silent no-op: the client asked for a state change that cannot
      // happen, and 409 lets it tell that apart from a successful publish.
      throw new DomainException({ code: 'COURSE_ALREADY_PUBLISHED', courseId: id });
    }
    if (course.status === 'archived') {
      throw new DomainException({ code: 'CANNOT_PUBLISH_ARCHIVED', courseId: id });
    }

    const published = await this.repo.update(id, {
      status: 'published',
      publishedAt: new Date(),
    });
    await this.coursesCache.onCourseChanged(
      courseEvent('course.published', published.id, published.ownerId),
    );
    return toCourseResponse(published);
  }

  async remove(user: AuthUser, id: string): Promise<void> {
    const course = await this.assertCanModify(id, user);
    await this.repo.delete(id);
    await this.coursesCache.onCourseChanged(
      courseEvent('course.deleted', asCourseId(id), course.ownerId),
    );
  }

  /** Used by other modules that need the course itself rather than its DTO. */
  async getOrThrow(id: string): Promise<Course> {
    const course = await this.repo.findById(id);
    if (!course) throw new DomainException({ code: 'COURSE_NOT_FOUND', courseId: id });
    return course;
  }

  /**
   * Role says *what kind of user* you are; ownership says *whose resource this
   * is*. The role part is already handled by RolesGuard, so what is left here
   * is ownership — with the "an admin may touch anything" rule stated once.
   */
  private async assertCanModify(id: string, user: AuthUser): Promise<Course> {
    const course = await this.getOrThrow(id);
    if (user.role !== 'admin' && course.ownerId !== asUserId(user.userId)) {
      throw new DomainException({ code: 'NOT_OWNER', resourceId: id });
    }
    return course;
  }
}
