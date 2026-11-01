import type { CourseId, EnrollmentId, UserId } from '../../../common/types/id';

export interface Enrollment {
  readonly id: EnrollmentId;
  readonly userId: UserId;
  readonly courseId: CourseId;
  readonly createdAt: Date;
}

/** Course fields an enrollment carries along when listing "my courses". */
export interface EnrolledCourse {
  readonly id: CourseId;
  readonly title: string;
  readonly status: 'draft' | 'published' | 'archived';
  readonly priceCents: number;
}

export interface EnrollmentWithCourse extends Enrollment {
  readonly course: EnrolledCourse;
}
