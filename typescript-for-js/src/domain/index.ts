/** Публичная поверхность доменного слоя: остальной код импортирует домен отсюда. */
export type { Environment } from './environment.ts';
export { ENVIRONMENTS, ENVIRONMENT_TITLES, environmentTitle, isEnvironment } from './environment.ts';

export type { DeploymentStatus } from './deployment-status.ts';
export {
  ACTIVE_STATUSES,
  DEPLOYMENT_STATUSES,
  STATUS_TITLES,
  isActiveStatus,
  isDeploymentStatus,
  statusTitle,
} from './deployment-status.ts';

export type { Brand, DeploymentId, ReleaseId } from './ids.ts';
export {
  isDeploymentId,
  isReleaseId,
  requireDeploymentId,
  toDeploymentId,
  toReleaseId,
} from './ids.ts';

export type { IsoDateTime, Release } from './release.ts';
export { shortSha } from './release.ts';

export type {
  ActiveDeployment,
  Deployment,
  FailedDeployment,
  FinishedDeployment,
  QueuedDeployment,
  RolledBackDeployment,
  RunningDeployment,
  SucceededDeployment,
} from './deployment.ts';
export { durationOf, isActive, isFailed, isFinished, startedOrQueuedAt } from './deployment.ts';

export type { SemVer } from './version.ts';
export { compareVersions, compareVersionStrings, formatVersion, isPrerelease, parseVersion } from './version.ts';

export type { DeploymentQuery } from './query.ts';
export { EMPTY_QUERY, applyQuery, matchesQuery, withQuery } from './query.ts';

export {
  DEFAULT_PAGE_SIZE,
  MAX_PAGE_SIZE,
  PROTECTED_ENVIRONMENTS,
  SLOW_DEPLOY_MS,
  isProtected,
} from './constants.ts';
