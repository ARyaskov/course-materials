import type { CourseId, LessonId } from '../../../common/types/id';

export interface Lesson {
  readonly id: LessonId;
  readonly courseId: CourseId;
  readonly title: string;
  readonly content: string;
  /** 1-based order inside its course; unique per course. */
  readonly position: number;
  readonly createdAt: Date;
}
