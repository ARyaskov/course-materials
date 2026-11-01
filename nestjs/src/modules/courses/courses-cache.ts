import { Injectable } from '@nestjs/common';
import { CacheService } from '../../infra/redis/cache.service';
import { cacheKeys } from '../../infra/redis/cache-keys';
import type { CourseEvent } from './domain/events';

/**
 * Turns course events into cache invalidation.
 *
 * Two levels, deliberately: the changed entity is dropped by key (precise, no
 * collateral damage), while the derived list keys are dropped by pattern
 * (coarse, but impossible to forget when a new filter combination appears).
 *
 * Always called *after* the write is committed — invalidating earlier lets a
 * concurrent reader repopulate the cache with the pre-change value.
 */
@Injectable()
export class CoursesCache {
  constructor(private readonly cache: CacheService) {}

  async onCourseChanged(event: CourseEvent): Promise<void> {
    await this.cache.invalidate(
      cacheKeys.course(event.courseId),
      cacheKeys.lessonsOfCourse(event.courseId),
    );
    await this.cache.invalidatePattern(cacheKeys.courseListPattern());
  }
}
