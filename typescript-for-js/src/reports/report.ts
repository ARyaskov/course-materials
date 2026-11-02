import type { Deployment } from '#domain/deployment.ts';
import { durationOf, startedOrQueuedAt } from '#domain/deployment.ts';
import { statusTitle } from '#domain/deployment-status.ts';
import { environmentTitle } from '#domain/environment.ts';
import { shortSha } from '#domain/release.ts';
import { formatCount, formatDateTime, formatDuration, formatPercent } from '#lib/format.ts';
import type { JsonValue } from '#lib/json.ts';

import type { DeploymentSummary, EnvironmentSummary } from './summary.ts';
import { orderedStatuses } from './summary.ts';

export interface ReportRow {
  readonly id: string;
  readonly environment: string;
  readonly status: string;
  readonly version: string;
  readonly commit: string;
  readonly author: string;
  readonly started: string;
  readonly duration: string;
}

const DEPLOY_FORMS = ['деплой', 'деплоя', 'деплоев'] as const;

export function toRow(deployment: Deployment): ReportRow {
  return {
    id: deployment.id,
    environment: environmentTitle(deployment.environment),
    status: statusTitle(deployment.status),
    version: deployment.release.version,
    commit: shortSha(deployment.release),
    author: deployment.requestedBy,
    started: formatDateTime(startedOrQueuedAt(deployment)),
    duration: formatDuration(durationOf(deployment)),
  };
}

export function toRows(deployments: readonly Deployment[]): readonly ReportRow[] {
  return deployments.map(toRow);
}

function renderEnvironment(environment: EnvironmentSummary): string {
  if (environment.total === 0) {
    return `${environment.environment}: нет деплоев`;
  }

  const counts = orderedStatuses(environment.byStatus)
    .filter(([, count]) => count > 0)
    .map(([status, count]) => `${statusTitle(status)} — ${count}`)
    .join(', ');

  return [
    `${environment.environment}: ${formatCount(environment.total, DEPLOY_FORMS)}`,
    `  успешных: ${formatPercent(environment.successRate)}`,
    `  среднее время: ${formatDuration(environment.averageDurationMs)}`,
    `  p95: ${formatDuration(environment.p95DurationMs)}`,
    `  последняя активность: ${formatDateTime(environment.lastActivityAt)}`,
    `  статусы: ${counts}`,
  ].join('\n');
}

/** Текстовый отчёт для CLI: то же содержимое, что и в JSON-выдаче. */
export function renderReport(summary: DeploymentSummary): string {
  const header = [
    'Shipyard — состояние деплоев',
    `Всего: ${formatCount(summary.total, DEPLOY_FORMS)}, успешных ${formatPercent(summary.successRate)}`,
  ];

  const environments = summary.environments.map(renderEnvironment);

  const failures =
    summary.failures.length === 0
      ? ['Падений нет']
      : [
          'Падения:',
          ...summary.failures.map(
            (deployment) =>
              `  ${deployment.id} (${deployment.environment}, код ${deployment.exitCode}): ${deployment.reason}`,
          ),
        ];

  const slow =
    summary.slow.length === 0
      ? []
      : [
          'Долгие деплои:',
          ...summary.slow.map(
            (deployment) => `  ${deployment.id}: ${formatDuration(durationOf(deployment))}`,
          ),
        ];

  return [...header, '', ...environments, '', ...failures, ...(slow.length > 0 ? ['', ...slow] : [])].join(
    '\n',
  );
}

/** Тот же отчёт в виде JSON: структура описана типом JsonValue. */
export function toReportJson(summary: DeploymentSummary): JsonValue {
  return {
    total: summary.total,
    successRate: summary.successRate,
    byStatus: summary.byStatus,
    environments: summary.environments.map((environment) => ({
      environment: environment.environment,
      total: environment.total,
      successRate: environment.successRate,
      averageDurationMs: environment.averageDurationMs,
      p95DurationMs: environment.p95DurationMs,
      lastActivityAt: environment.lastActivityAt,
      byStatus: environment.byStatus,
    })),
    failures: summary.failures.map((deployment) => ({
      id: deployment.id,
      environment: deployment.environment,
      reason: deployment.reason,
      exitCode: deployment.exitCode,
    })),
  };
}
