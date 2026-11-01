import { Injectable } from '@nestjs/common';
import { EnrollmentRepository } from './enrollment.repository';
import { CoursesService } from '../courses/courses.service';
import { DomainException } from '../../common/errors/domain-error';
import {
  assertCourseIsEnrollable,
  assertNoPaymentRequired,
  assertNotAlreadyEnrolled,
} from './domain/rules';
import { toEnrollmentResponse, type EnrollmentResponse } from './dto/enrollment.response';

@Injectable()
export class EnrollmentService {
  constructor(
    private readonly repo: EnrollmentRepository,
    private readonly courses: CoursesService,
  ) {}

  async enroll(userId: string, courseId: string): Promise<EnrollmentResponse> {
    const course = await this.courses.getOrThrow(courseId);

    assertCourseIsEnrollable(course);
    assertNoPaymentRequired(course);
    assertNotAlreadyEnrolled(await this.repo.find(userId, courseId), userId, courseId);

    const enrollment = await this.repo.create(userId, courseId);
    return toEnrollmentResponse(enrollment);
  }

  async listMine(userId: string): Promise<EnrollmentResponse[]> {
    const rows = await this.repo.listByUser(userId);
    return rows.map((row) => toEnrollmentResponse(row, row.course));
  }

  async unenroll(userId: string, courseId: string): Promise<void> {
    const existing = await this.repo.find(userId, courseId);
    if (!existing) {
      // The course may well exist — what is missing is *this user's* enrollment,
      // and the code says exactly that.
      throw new DomainException({ code: 'ENROLLMENT_NOT_FOUND', userId, courseId });
    }
    await this.repo.delete(existing.id);
  }
}
