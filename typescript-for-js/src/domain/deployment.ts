import type { DeploymentStatus } from './deployment-status.ts';
import type { Environment } from './environment.ts';
import type { DeploymentId, ReleaseId } from './ids.ts';
import type { IsoDateTime, Release } from './release.ts';

interface DeploymentBase {
  readonly id: DeploymentId;
  readonly environment: Environment;
  readonly release: Release;
  readonly requestedBy: string;
  readonly comment: string | null;
}

interface Timing {
  readonly startedAt: IsoDateTime;
  readonly finishedAt: IsoDateTime;
  readonly durationMs: number;
}

export type QueuedDeployment = DeploymentBase & {
  readonly status: 'queued';
  readonly queuedAt: IsoDateTime;
};

export type RunningDeployment = DeploymentBase & {
  readonly status: 'running';
  readonly startedAt: IsoDateTime;
};

export type SucceededDeployment = DeploymentBase & Timing & { readonly status: 'succeeded' };

export type FailedDeployment = DeploymentBase &
  Timing & {
    readonly status: 'failed';
    readonly reason: string;
    readonly exitCode: number;
  };

export type RolledBackDeployment = DeploymentBase &
  Timing & {
    readonly status: 'rolled_back';
    readonly revertedTo: ReleaseId;
  };

export type Deployment =
  | QueuedDeployment
  | RunningDeployment
  | SucceededDeployment
  | FailedDeployment
  | RolledBackDeployment;

export type FinishedDeployment = Extract<
  Deployment,
  { readonly status: 'succeeded' | 'failed' | 'rolled_back' }
>;

export type ActiveDeployment = Exclude<Deployment, FinishedDeployment>;

export function isFinished(deployment: Deployment): deployment is FinishedDeployment {
  return (
    deployment.status === 'succeeded' ||
    deployment.status === 'failed' ||
    deployment.status === 'rolled_back'
  );
}

export function isFailed(deployment: Deployment): deployment is FailedDeployment {
  return deployment.status === 'failed';
}

export function isActive(deployment: Deployment): deployment is ActiveDeployment {
  return !isFinished(deployment);
}

/** Момент, с которого деплой существует: старт либо постановка в очередь. */
export function startedOrQueuedAt(deployment: Deployment): IsoDateTime {
  return deployment.status === 'queued' ? deployment.queuedAt : deployment.startedAt;
}

/** Длительность, если деплой завершился. */
export function durationOf(deployment: Deployment): number | null {
  return isFinished(deployment) ? deployment.durationMs : null;
}

export function statusOf(status: DeploymentStatus): DeploymentStatus {
  return status;
}
