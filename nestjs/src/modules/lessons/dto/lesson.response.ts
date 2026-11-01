import type { Lesson } from '../domain/lesson';

export interface LessonResponse {
  readonly id: string;
  readonly courseId: string;
  readonly title: string;
  readonly content: string;
  readonly position: number;
  readonly createdAt: string;
}

export function toLessonResponse(lesson: Lesson): LessonResponse {
  return {
    id: lesson.id,
    courseId: lesson.courseId,
    title: lesson.title,
    content: lesson.content,
    position: lesson.position,
    // Dates cross the wire as ISO strings — and survive a round trip through
    // the cache, where a Date would come back as a string anyway.
    createdAt: new Date(lesson.createdAt).toISOString(),
  };
}
