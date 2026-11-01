import { DomainException } from '../../../common/errors/domain-error';
import { Money } from '../../../common/domain/money';
import type { Course } from '../../courses/domain/course';

/**
 * The rules that decide whether a user may enrol, kept out of the service so
 * they can be read (and unit-tested) as a list of business statements rather
 * than reconstructed from a chain of `if`s around database calls.
 *
 * They take plain domain objects and either return or throw — no Prisma, no
 * HTTP, no Redis.
 */

/** A course accepts enrolments only while it is published. */
export function assertCourseIsEnrollable(course: Course): void {
  if (course.status !== 'published') {
    throw new DomainException({ code: 'COURSE_NOT_PUBLISHED', courseId: course.id });
  }
}

/**
 * Free courses can be joined directly; a priced course needs a completed
 * payment, which the billing flow owns.
 */
export function assertNoPaymentRequired(course: Course): void {
  const price = Money.of(course.priceCents, 'USD');
  if (!price.isZero()) {
    throw new DomainException({ code: 'PAYMENT_REQUIRED', priceCents: price.amountCents });
  }
}

/** Enrolment is idempotent by intent but not by accident: a repeat is a conflict. */
export function assertNotAlreadyEnrolled(
  existing: unknown,
  userId: string,
  courseId: string,
): void {
  if (existing) {
    throw new DomainException({ code: 'USER_ALREADY_ENROLLED', userId, courseId });
  }
}
