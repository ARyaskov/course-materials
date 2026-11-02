import type { Deployment, FailedDeployment } from '#domain/deployment.ts';
import { durationOf, isFailed, isFinished, startedOrQueuedAt } from '#domain/deployment.ts';
import { DEPLOYMENT_STATUSES } from '#domain/deployment-status.ts';
import type { DeploymentStatus } from '#domain/deployment-status.ts';
import { ENVIRONMENTS } from '#domain/environment.ts';
import type { Environment } from '#domain/environment.ts';
import { SLOW_DEPLOY_MS } from '#domain/constants.ts';
import type { IsoDateTime } from '#domain/release.ts';
import { mapNotNull } from '#lib/collections.ts';
import { average, percentile, ratio } from '#lib/number.ts';

export type StatusCounts = Record<DeploymentStatus, number>;

export interface EnvironmentSummary {
  readonly environment: Environment;
  readonly total: number;
  readonly byStatus: StatusCounts;
  readonly successRate: number;
  readonly averageDurationMs: number | null;
  readonly p95DurationMs: number | null;
  readonly lastActivityAt: IsoDateTime | null;
}

export interface DeploymentSummary {
  readonly total: number;
  readonly byStatus: StatusCounts;
  readonly environments: readonly EnvironmentSummary[];
  readonly failures: readonly FailedDeployment[];
  readonly slow: readonly Deployment[];
  readonly successRate: number;
}

function emptyCounts(): StatusCounts {
  return {
    queued: 0,
    running: 0,
    succeeded: 0,
    failed: 0,
    rolled_back: 0,
  };
}

function countStatuses(deployments: readonly Deployment[]): StatusCounts {
  const counts = emptyCounts();

  for (const deployment of deployments) {
    counts[deployment.status] += 1;
  }

  return counts;
}

function successRateOf(counts: StatusCounts): number {
  const finished = counts.succeeded + counts.failed + counts.rolled_back;
  return ratio(counts.succeeded, finished);
}

function latestActivity(deployments: readonly Deployment[]): IsoDateTime | null {
  return deployments.reduce<IsoDateTime | null>((latest, deployment) => {
    const moment = startedOrQueuedAt(deployment);
    return latest === null || moment > latest ? moment : latest;
  }, null);
}

function summarizeEnvironment(
  environment: Environment,
  deployments: readonly Deployment[],
): EnvironmentSummary {
  const durations = mapNotNull(deployments, durationOf);
  const counts = countStatuses(deployments);

  return {
    environment,
    total: deployments.length,
    byStatus: counts,
    successRate: successRateOf(counts),
    averageDurationMs: average(durations),
    p95DurationMs: percentile(durations, 0.95),
    lastActivityAt: latestActivity(deployments),
  };
}

/** Единственное место, где считается агрегированная статистика по деплоям. */
export function summarize(deployments: readonly Deployment[]): DeploymentSummary {
  const counts = countStatuses(deployments);

  const environments = ENVIRONMENTS.map((environment) =>
    summarizeEnvironment(
      environment,
      deployments.filter((deployment) => deployment.environment === environment),
    ),
  );

  return {
    total: deployments.length,
    byStatus: counts,
    environments,
    failures: deployments.filter(isFailed),
    slow: deployments.filter(
      (deployment) => isFinished(deployment) && deployment.durationMs >= SLOW_DEPLOY_MS,
    ),
    successRate: successRateOf(counts),
  };
}

/** Статусы в порядке, в котором их удобно показывать в отчёте. */
export function orderedStatuses(counts: StatusCounts): readonly (readonly [DeploymentStatus, number])[] {
  return DEPLOYMENT_STATUSES.map((status) => [status, counts[status]] as const);
}
