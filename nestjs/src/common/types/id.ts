/**
 * Branded id types. They are plain strings at runtime but distinct at compile
 * time, so a `UserId` can't be accidentally passed where a `CourseId` is needed.
 */
type Brand<T, B> = T & { readonly __brand: B };

export type UserId = Brand<string, 'UserId'>;
export type CourseId = Brand<string, 'CourseId'>;
export type LessonId = Brand<string, 'LessonId'>;
export type EnrollmentId = Brand<string, 'EnrollmentId'>;

export const asUserId = (s: string): UserId => s as UserId;
export const asCourseId = (s: string): CourseId => s as CourseId;
export const asLessonId = (s: string): LessonId => s as LessonId;
export const asEnrollmentId = (s: string): EnrollmentId => s as EnrollmentId;
