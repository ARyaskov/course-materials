export const DEPLOYMENT_STATUSES = [
  'queued',
  'running',
  'succeeded',
  'failed',
  'rolled_back',
] as const;

export type DeploymentStatus = (typeof DEPLOYMENT_STATUSES)[number];

export const ACTIVE_STATUSES = ['queued', 'running'] as const satisfies readonly DeploymentStatus[];

export type ActiveStatus = (typeof ACTIVE_STATUSES)[number];
export type FinishedStatus = Exclude<DeploymentStatus, ActiveStatus>;

export const STATUS_TITLES = {
  queued: 'в очереди',
  running: 'выполняется',
  succeeded: 'успешно',
  failed: 'ошибка',
  rolled_back: 'откат',
} as const satisfies Record<DeploymentStatus, string>;

export function statusTitle(status: DeploymentStatus): string {
  return STATUS_TITLES[status];
}

export function isDeploymentStatus(value: unknown): value is DeploymentStatus {
  return typeof value === 'string' && (DEPLOYMENT_STATUSES as readonly string[]).includes(value);
}

export function isActiveStatus(status: DeploymentStatus): status is ActiveStatus {
  return (ACTIVE_STATUSES as readonly DeploymentStatus[]).includes(status);
}
