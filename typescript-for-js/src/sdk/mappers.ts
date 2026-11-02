import type { Deployment } from '#domain/deployment.ts';
import { durationOf, startedOrQueuedAt } from '#domain/deployment.ts';

import type { DeploymentSummaryDto, PublicDeploymentDto } from './dto.ts';

export function toSummaryDto(deployment: Deployment): DeploymentSummaryDto {
  return {
    id: deployment.id,
    environment: deployment.environment,
    status: deployment.status,
    version: deployment.release.version,
    author: deployment.requestedBy,
    startedAt: startedOrQueuedAt(deployment),
    durationMs: durationOf(deployment),
  };
}

/** Убираем внутреннее поле, сохраняя дискриминированное объединение. */
export function toPublicDto(deployment: Deployment): PublicDeploymentDto {
  const { comment: _comment, ...rest } = deployment;
  return rest;
}

export function toSummaryDtos(deployments: readonly Deployment[]): readonly DeploymentSummaryDto[] {
  return deployments.map(toSummaryDto);
}
