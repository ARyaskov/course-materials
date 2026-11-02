import { z } from 'zod';

import { DEPLOYMENT_STATUSES } from '#domain/deployment-status.ts';
import { ENVIRONMENTS } from '#domain/environment.ts';
import { isDeploymentId, isReleaseId } from '#domain/ids.ts';
import type { DeploymentId, ReleaseId } from '#domain/ids.ts';

/** Идентификаторы проверяются теми же предикатами, что и в домене. */
export const deploymentIdSchema = z.custom<DeploymentId>(
  (value) => typeof value === 'string' && isDeploymentId(value),
  { message: 'ожидался идентификатор вида dep_1a2b' },
);

export const releaseIdSchema = z.custom<ReleaseId>(
  (value) => typeof value === 'string' && isReleaseId(value),
  { message: 'ожидался идентификатор вида rel_42' },
);

export const isoDateTimeSchema = z.iso.datetime({ offset: true });

export const environmentSchema = z.enum(ENVIRONMENTS);
export const statusSchema = z.enum(DEPLOYMENT_STATUSES);

export const releaseSchema = z.object({
  id: releaseIdSchema,
  version: z.string().min(1),
  commit_sha: z.string().regex(/^[0-9a-f]{7,40}$/, 'ожидался hex-хеш коммита'),
  author: z.string().min(1),
});

const baseFields = {
  id: deploymentIdSchema,
  environment: environmentSchema,
  release: releaseSchema,
  requested_by: z.string().min(1),
  comment: z
    .string()
    .nullish()
    .transform((value) => value ?? null),
};

const timingFields = {
  started_at: isoDateTimeSchema,
  finished_at: isoDateTimeSchema,
  duration_ms: z.number().int().nonnegative(),
};

export const queuedSchema = z.object({
  ...baseFields,
  status: z.literal('queued'),
  queued_at: isoDateTimeSchema,
});

export const runningSchema = z.object({
  ...baseFields,
  status: z.literal('running'),
  started_at: isoDateTimeSchema,
});

export const succeededSchema = z.object({
  ...baseFields,
  ...timingFields,
  status: z.literal('succeeded'),
});

export const failedSchema = z.object({
  ...baseFields,
  ...timingFields,
  status: z.literal('failed'),
  reason: z.string().min(1),
  exit_code: z.number().int(),
});

export const rolledBackSchema = z.object({
  ...baseFields,
  ...timingFields,
  status: z.literal('rolled_back'),
  reverted_to: releaseIdSchema,
});

/** Дискриминированное объединение: ветка выбирается по полю status. */
export const deploymentSchema = z.discriminatedUnion('status', [
  queuedSchema,
  runningSchema,
  succeededSchema,
  failedSchema,
  rolledBackSchema,
]);

export const pageMetaSchema = z.object({
  total: z.number().int().nonnegative(),
  limit: z.number().int().positive(),
  offset: z.number().int().nonnegative().default(0),
});

export const deploymentListSchema = z.object({
  data: z.array(deploymentSchema),
  meta: pageMetaSchema.nullish().transform((value) => value ?? null),
});

export const errorPayloadSchema = z.object({
  error: z.object({
    code: z.string().min(1),
    message: z.string().min(1),
  }),
});
