import { BadRequestException } from '@nestjs/common';
import type { ValidationError } from 'class-validator';

/**
 * A single failed constraint, flattened into the shape the API contract
 * promises: `{ field, rule, message }`.
 */
export interface ValidationFieldError {
  readonly field: string;
  readonly rule: string;
  readonly message: string;
}

/**
 * Turns class-validator output into the documented validation envelope:
 *
 *   { "error": { "code": "VALIDATION_ERROR",
 *                "message": "Invalid request payload",
 *                "details": { "fields": [ { field, rule, message } ] },
 *                "requestId": "..." } }
 *
 * A generic `BAD_REQUEST` on every malformed payload gives clients nothing to
 * branch on; the per-field list is what makes the error actionable.
 */
export function buildValidationException(errors: ValidationError[]): BadRequestException {
  return new BadRequestException({
    code: 'VALIDATION_ERROR',
    message: 'Invalid request payload',
    details: { fields: flattenValidationErrors(errors) },
  });
}

export function flattenValidationErrors(
  errors: ValidationError[],
  parentPath = '',
): ValidationFieldError[] {
  const flat: ValidationFieldError[] = [];

  for (const error of errors) {
    const field = parentPath ? `${parentPath}.${error.property}` : error.property;

    for (const [rule, message] of Object.entries(error.constraints ?? {})) {
      flat.push({ field, rule, message });
    }

    // Nested objects and arrays report their own children.
    if (error.children?.length) {
      flat.push(...flattenValidationErrors(error.children, field));
    }
  }

  return flat;
}
