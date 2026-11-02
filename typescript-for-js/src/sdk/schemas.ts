import { z } from 'zod';

import { deploymentListSchema, deploymentSchema, isoDateTimeSchema } from '#api/schemas.ts';

/** SDK принимает те же данные, что и внутренний слой api, но описывает свой ответ. */
export const listResponseSchema = deploymentListSchema;
export const itemResponseSchema = deploymentSchema;

export const summaryResponseSchema = z.object({
  total: z.number().int().nonnegative(),
  successRate: z.number().min(0).max(1),
  environments: z.array(
    z.object({
      environment: z.string(),
      total: z.number().int().nonnegative(),
      successRate: z.number().min(0).max(1),
      averageDurationMs: z.number().nullable(),
      p95DurationMs: z.number().nullable(),
      lastActivityAt: isoDateTimeSchema.nullable(),
    }),
  ),
});

export type SummaryResponse = z.infer<typeof summaryResponseSchema>;
