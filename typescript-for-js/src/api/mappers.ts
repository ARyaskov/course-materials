import type { Deployment } from '#domain/deployment.ts';
import type { Release } from '#domain/release.ts';
import { assertNever } from '#lib/assert-never.ts';

import type { DeploymentDto, ReleaseDto } from './dto.ts';

export function toRelease(dto: ReleaseDto): Release {
  return {
    id: dto.id,
    version: dto.version,
    commitSha: dto.commit_sha,
    author: dto.author,
  };
}

export function fromRelease(release: Release): ReleaseDto {
  return {
    id: release.id,
    version: release.version,
    commit_sha: release.commitSha,
    author: release.author,
  };
}

/** DTO уже проверен схемой, поэтому здесь только переименование полей. */
export function toDeployment(dto: DeploymentDto): Deployment {
  const base = {
    id: dto.id,
    environment: dto.environment,
    release: toRelease(dto.release),
    requestedBy: dto.requested_by,
    comment: dto.comment,
  } as const;

  switch (dto.status) {
    case 'queued':
      return { ...base, status: 'queued', queuedAt: dto.queued_at };

    case 'running':
      return { ...base, status: 'running', startedAt: dto.started_at };

    case 'succeeded':
      return {
        ...base,
        status: 'succeeded',
        startedAt: dto.started_at,
        finishedAt: dto.finished_at,
        durationMs: dto.duration_ms,
      };

    case 'failed':
      return {
        ...base,
        status: 'failed',
        startedAt: dto.started_at,
        finishedAt: dto.finished_at,
        durationMs: dto.duration_ms,
        reason: dto.reason,
        exitCode: dto.exit_code,
      };

    case 'rolled_back':
      return {
        ...base,
        status: 'rolled_back',
        startedAt: dto.started_at,
        finishedAt: dto.finished_at,
        durationMs: dto.duration_ms,
        revertedTo: dto.reverted_to,
      };

    default:
      return assertNever(dto, 'toDeployment');
  }
}

/** Обратное отображение: нужно нашему собственному HTTP-серверу и фикстурам. */
export function fromDeployment(deployment: Deployment): DeploymentDto {
  const base = {
    id: deployment.id,
    environment: deployment.environment,
    release: fromRelease(deployment.release),
    requested_by: deployment.requestedBy,
    comment: deployment.comment,
  } as const;

  switch (deployment.status) {
    case 'queued':
      return { ...base, status: 'queued', queued_at: deployment.queuedAt };

    case 'running':
      return { ...base, status: 'running', started_at: deployment.startedAt };

    case 'succeeded':
      return {
        ...base,
        status: 'succeeded',
        started_at: deployment.startedAt,
        finished_at: deployment.finishedAt,
        duration_ms: deployment.durationMs,
      };

    case 'failed':
      return {
        ...base,
        status: 'failed',
        started_at: deployment.startedAt,
        finished_at: deployment.finishedAt,
        duration_ms: deployment.durationMs,
        reason: deployment.reason,
        exit_code: deployment.exitCode,
      };

    case 'rolled_back':
      return {
        ...base,
        status: 'rolled_back',
        started_at: deployment.startedAt,
        finished_at: deployment.finishedAt,
        duration_ms: deployment.durationMs,
        reverted_to: deployment.revertedTo,
      };

    default:
      return assertNever(deployment, 'fromDeployment');
  }
}

export function toDeployments(dtos: readonly DeploymentDto[]): readonly Deployment[] {
  return dtos.map(toDeployment);
}
