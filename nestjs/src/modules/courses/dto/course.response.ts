import type { Course } from '../domain/course';

export interface CourseResponse {
  readonly id: string;
  readonly ownerId: string;
  readonly title: string;
  readonly description: string;
  readonly priceCents: number;
  readonly status: 'draft' | 'published' | 'archived';
  readonly createdAt: string; // ISO 8601
  readonly publishedAt: string | null;
}

export function toCourseResponse(c: Course): CourseResponse {
  return {
    id: c.id,
    ownerId: c.ownerId,
    title: c.title,
    description: c.description,
    priceCents: c.priceCents,
    status: c.status,
    createdAt: c.createdAt.toISOString(),
    publishedAt: c.publishedAt ? c.publishedAt.toISOString() : null,
  };
}
