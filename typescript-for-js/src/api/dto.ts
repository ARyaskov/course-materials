import type { z } from 'zod';

import type {
  deploymentListSchema,
  deploymentSchema,
  errorPayloadSchema,
  failedSchema,
  pageMetaSchema,
  queuedSchema,
  releaseSchema,
  rolledBackSchema,
  runningSchema,
  succeededSchema,
} from './schemas.ts';

/** Форма данных «на проводе»: snake_case, как отдаёт сервер. */
export type ReleaseDto = z.infer<typeof releaseSchema>;
export type QueuedDto = z.infer<typeof queuedSchema>;
export type RunningDto = z.infer<typeof runningSchema>;
export type SucceededDto = z.infer<typeof succeededSchema>;
export type FailedDto = z.infer<typeof failedSchema>;
export type RolledBackDto = z.infer<typeof rolledBackSchema>;
export type DeploymentDto = z.infer<typeof deploymentSchema>;
export type PageMetaDto = z.infer<typeof pageMetaSchema>;
export type DeploymentListDto = z.infer<typeof deploymentListSchema>;
export type ErrorPayloadDto = z.infer<typeof errorPayloadSchema>;

/** Вход схемы отличается от выхода там, где есть transform и default. */
export type DeploymentInputDto = z.input<typeof deploymentSchema>;
