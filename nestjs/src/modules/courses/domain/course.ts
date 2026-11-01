import type { CourseId, UserId } from '../../../common/types/id';

export type CourseStatus = 'draft' | 'published' | 'archived';

export interface Course {
  readonly id: CourseId;
  readonly ownerId: UserId;
  readonly title: string;
  readonly description: string;
  readonly priceCents: number;
  readonly status: CourseStatus;
  readonly createdAt: Date;
  readonly publishedAt: Date | null;
}
