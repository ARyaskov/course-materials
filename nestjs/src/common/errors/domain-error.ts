/**
 * Domain errors are a closed, typed set. Services throw `DomainException`;
 * the global filter maps each code to an HTTP response (see map-domain-to-http).
 *
 * This keeps business rules independent of HTTP and gives the API a stable,
 * machine-readable error contract.
 */
export type DomainError =
  | { code: 'USER_NOT_FOUND'; userId: string }
  | { code: 'COURSE_NOT_FOUND'; courseId: string }
  | { code: 'LESSON_NOT_FOUND'; lessonId: string }
  | { code: 'EMAIL_ALREADY_TAKEN'; email: string }
  | { code: 'INVALID_CREDENTIALS' }
  | { code: 'USER_ALREADY_ENROLLED'; userId: string; courseId: string }
  | { code: 'COURSE_NOT_PUBLISHED'; courseId: string }
  | { code: 'COURSE_ALREADY_PUBLISHED'; courseId: string }
  | { code: 'ENROLLMENT_NOT_FOUND'; userId: string; courseId: string }
  | { code: 'RATE_LIMITED'; retryAfterSeconds: number }
  | { code: 'CANNOT_PUBLISH_ARCHIVED'; courseId: string }
  | { code: 'PAYMENT_REQUIRED'; priceCents: number }
  | { code: 'PAYMENT_ALREADY_PROCESSED'; paymentId: string }
  | { code: 'INVALID_REFRESH_TOKEN' }
  | { code: 'NOT_AN_INSTRUCTOR'; userId: string }
  | { code: 'NOT_OWNER'; resourceId: string }
  | { code: 'INVALID_MONEY_AMOUNT' }
  | { code: 'NEGATIVE_MONEY_AMOUNT' }
  | { code: 'CURRENCY_MISMATCH' };

export type DomainErrorCode = DomainError['code'];

export class DomainException extends Error {
  constructor(public readonly error: DomainError) {
    super(error.code);
    this.name = 'DomainException';
  }
}
