import type { CourseId, UserId } from '../../../common/types/id';

/**
 * Facts about what happened to a course, expressed in domain terms and in the
 * past tense. They carry no HTTP, Prisma or Redis concepts, which is what lets
 * several consumers (today: cache invalidation) react to one write without the
 * service knowing about any of them.
 */
export type CourseEvent =
  | { type: 'course.created'; courseId: CourseId; ownerId: UserId; occurredAt: Date }
  | { type: 'course.updated'; courseId: CourseId; ownerId: UserId; occurredAt: Date }
  | { type: 'course.published'; courseId: CourseId; ownerId: UserId; occurredAt: Date }
  | { type: 'course.deleted'; courseId: CourseId; ownerId: UserId; occurredAt: Date };

export type CourseEventType = CourseEvent['type'];

export function courseEvent(
  type: CourseEventType,
  courseId: CourseId,
  ownerId: UserId,
): CourseEvent {
  return { type, courseId, ownerId, occurredAt: new Date() };
}
