/**
 * Cache key vocabulary. Keys are hierarchical (`namespace:version:entity:id`),
 * carry a format version so a rolling deploy can change the cached shape
 * without migrating anything, and are built in exactly one place so a forgotten
 * query parameter can't silently collide two different results.
 */
const PREFIX = 'cache:v1';

export const cacheKeys = {
  course: (courseId: string): string => `${PREFIX}:course:${courseId}`,

  courseList: (params: {
    status?: string;
    search?: string;
    limit: number;
    offset: number;
    sortBy: string;
    sortOrder: string;
  }): string =>
    [
      `${PREFIX}:courses:list`,
      `status=${params.status ?? 'any'}`,
      `search=${params.search ?? ''}`,
      `limit=${params.limit}`,
      `offset=${params.offset}`,
      `sort=${params.sortBy}.${params.sortOrder}`,
    ].join(':'),

  /** Pattern matching every cached course list, for coarse invalidation. */
  courseListPattern: (): string => `${PREFIX}:courses:list:*`,

  lessonsOfCourse: (courseId: string): string => `${PREFIX}:lessons:course:${courseId}`,
} as const;

/**
 * TTLs in seconds. Short enough that a missed invalidation heals on its own,
 * long enough that the cache actually absorbs read traffic.
 */
export const cacheTtl = {
  course: 600,
  courseList: 300,
  lessons: 300,
  /** Negative caching: remember "not found" only briefly. */
  notFound: 30,
} as const;
