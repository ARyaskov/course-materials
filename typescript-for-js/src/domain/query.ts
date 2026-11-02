import type { Deployment } from './deployment.ts';
import type { DeploymentStatus } from './deployment-status.ts';
import type { Environment } from './environment.ts';
import { DEFAULT_PAGE_SIZE } from './constants.ts';

export interface DeploymentQuery {
  readonly environment: Environment | null;
  readonly status: DeploymentStatus | null;
  readonly author: string | null;
  readonly limit: number;
  readonly offset: number;
}

export const EMPTY_QUERY: DeploymentQuery = {
  environment: null,
  status: null,
  author: null,
  limit: DEFAULT_PAGE_SIZE,
  offset: 0,
};

export function withQuery(
  base: DeploymentQuery,
  patch: Partial<DeploymentQuery>,
): DeploymentQuery {
  return { ...base, ...patch };
}

export function matchesQuery(deployment: Deployment, query: DeploymentQuery): boolean {
  if (query.environment !== null && deployment.environment !== query.environment) return false;
  if (query.status !== null && deployment.status !== query.status) return false;

  if (query.author !== null) {
    const author = query.author.toLowerCase();
    const matchesAuthor =
      deployment.requestedBy.toLowerCase().includes(author) ||
      deployment.release.author.toLowerCase().includes(author);
    if (!matchesAuthor) return false;
  }

  return true;
}

export function applyQuery(
  deployments: readonly Deployment[],
  query: DeploymentQuery,
): readonly Deployment[] {
  const matched = deployments.filter((deployment) => matchesQuery(deployment, query));
  return matched.slice(query.offset, query.offset + query.limit);
}
