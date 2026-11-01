import type { DomainError } from './domain-error';

export interface HttpMapping {
  status: number;
  body: {
    code: DomainError['code'];
    message: string;
    details?: Record<string, unknown>;
  };
}

export function mapDomainToHttp(error: DomainError): HttpMapping {
  switch (error.code) {
    case 'USER_NOT_FOUND':
      return {
        status: 404,
        body: {
          code: error.code,
          message: 'User not found',
          details: { userId: error.userId },
        },
      };
    case 'COURSE_NOT_FOUND':
      return {
        status: 404,
        body: {
          code: error.code,
          message: 'Course not found',
          details: { courseId: error.courseId },
        },
      };
    case 'LESSON_NOT_FOUND':
      return {
        status: 404,
        body: {
          code: error.code,
          message: 'Lesson not found',
          details: { lessonId: error.lessonId },
        },
      };
    case 'EMAIL_ALREADY_TAKEN':
      return {
        status: 409,
        body: {
          code: error.code,
          message: 'Email is already taken',
          details: { email: error.email },
        },
      };
    case 'INVALID_CREDENTIALS':
      return { status: 401, body: { code: error.code, message: 'Invalid email or password' } };
    case 'USER_ALREADY_ENROLLED':
      return {
        status: 409,
        body: { code: error.code, message: 'User is already enrolled in this course' },
      };
    case 'COURSE_NOT_PUBLISHED':
      return { status: 409, body: { code: error.code, message: 'Course is not published' } };
    case 'COURSE_ALREADY_PUBLISHED':
      return {
        status: 409,
        body: {
          code: error.code,
          message: 'Course is already published',
          details: { courseId: error.courseId },
        },
      };
    case 'ENROLLMENT_NOT_FOUND':
      return {
        status: 404,
        body: {
          code: error.code,
          message: 'Enrollment not found',
          details: { courseId: error.courseId },
        },
      };
    case 'RATE_LIMITED':
      return {
        status: 429,
        body: {
          code: error.code,
          message: 'Too many requests',
          details: { retryAfter: error.retryAfterSeconds },
        },
      };
    case 'CANNOT_PUBLISH_ARCHIVED':
      return {
        status: 409,
        body: { code: error.code, message: 'Archived course cannot be published' },
      };
    case 'PAYMENT_REQUIRED':
      return {
        status: 402,
        body: {
          code: error.code,
          message: 'Payment is required',
          details: { priceCents: error.priceCents },
        },
      };
    case 'PAYMENT_ALREADY_PROCESSED':
      return {
        status: 409,
        body: {
          code: error.code,
          message: 'Payment was already processed',
          details: { paymentId: error.paymentId },
        },
      };
    case 'INVALID_REFRESH_TOKEN':
      return { status: 401, body: { code: error.code, message: 'Refresh token is invalid' } };
    case 'NOT_AN_INSTRUCTOR':
      return {
        status: 403,
        body: { code: error.code, message: 'Only instructors can perform this action' },
      };
    case 'NOT_OWNER':
      return {
        status: 403,
        body: {
          code: error.code,
          message: 'You are not the owner of this resource',
          details: { resourceId: error.resourceId },
        },
      };
    case 'INVALID_MONEY_AMOUNT':
      return {
        status: 400,
        body: { code: error.code, message: 'Money amount must be an integer number of cents' },
      };
    case 'NEGATIVE_MONEY_AMOUNT':
      return {
        status: 400,
        body: { code: error.code, message: 'Money amount cannot be negative' },
      };
    case 'CURRENCY_MISMATCH':
      return {
        status: 400,
        body: {
          code: error.code,
          message: 'Cannot operate on amounts with different currencies',
        },
      };
  }
}
