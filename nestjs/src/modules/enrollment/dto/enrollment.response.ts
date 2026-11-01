import type { EnrolledCourse, Enrollment } from '../domain/enrollment';

export interface EnrollmentCourseSummary {
  readonly id: string;
  readonly title: string;
  readonly status: 'draft' | 'published' | 'archived';
  readonly priceCents: number;
}

export interface EnrollmentResponse {
  readonly id: string;
  readonly userId: string;
  readonly courseId: string;
  readonly createdAt: string;
  readonly course?: EnrollmentCourseSummary;
}

export function toEnrollmentResponse(
  enrollment: Enrollment,
  course?: EnrolledCourse,
): EnrollmentResponse {
  return {
    id: enrollment.id,
    userId: enrollment.userId,
    courseId: enrollment.courseId,
    createdAt: enrollment.createdAt.toISOString(),
    ...(course
      ? {
          course: {
            id: course.id,
            title: course.title,
            status: course.status,
            priceCents: course.priceCents,
          },
        }
      : {}),
  };
}
