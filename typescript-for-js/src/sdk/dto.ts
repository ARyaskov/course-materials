import type { Deployment } from '#domain/deployment.ts';
import type { DeploymentStatus } from '#domain/deployment-status.ts';
import type { Environment } from '#domain/environment.ts';
import type { IsoDateTime } from '#domain/release.ts';
import type { DistributiveOmit } from '#lib/types.ts';

/** Публичный DTO собирается из доменной модели, а не пишется руками заново. */
export type DeploymentSummaryDto = Pick<Deployment, 'id' | 'environment' | 'status'> & {
  readonly version: string;
  readonly author: string;
  readonly startedAt: IsoDateTime;
  readonly durationMs: number | null;
};

/** Тот же деплой, но без внутреннего комментария: он не уходит наружу. */
export type PublicDeploymentDto = DistributiveOmit<Deployment, 'comment'>;

export interface ListDeploymentsRequest {
  readonly environment?: Environment;
  readonly status?: DeploymentStatus;
  readonly author?: string;
  readonly limit?: number;
  readonly offset?: number;
}

export interface PageInfoDto {
  readonly total: number;
  readonly limit: number;
  readonly offset: number;
}

export interface ListDeploymentsResponse {
  readonly items: readonly DeploymentSummaryDto[];
  readonly page: PageInfoDto | null;
}

export interface SdkErrorDto {
  readonly code: string;
  readonly message: string;
}
