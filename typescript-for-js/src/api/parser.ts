import type { ZodType } from 'zod';

import { err, ok } from '#lib/result.ts';
import type { Result } from '#lib/result.ts';

import { invalidShapeError } from './errors.ts';
import type { ApiError } from './errors.ts';

interface IssueLike {
  readonly path: readonly PropertyKey[];
  readonly message: string;
}

/** Человекочитаемое описание проблемы: путь до поля плюс текст схемы. */
export function formatIssues(issues: readonly IssueLike[]): readonly string[] {
  return issues.map((issue) => {
    const path = issue.path.map(String).join('.');
    return path.length === 0 ? issue.message : `${path}: ${issue.message}`;
  });
}

/** Единственная точка входа для проверки внешних данных схемой. */
export function parseWith<T>(schema: ZodType<T>, input: unknown): Result<T, ApiError> {
  const parsed = schema.safeParse(input);
  if (parsed.success) return ok(parsed.data);
  return err(invalidShapeError(formatIssues(parsed.error.issues)));
}
