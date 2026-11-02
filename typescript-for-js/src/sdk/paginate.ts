import { hasMore, nextOffset } from '#api/response.ts';
import type { Deployment } from '#domain/deployment.ts';

import type { ShipyardClient } from './client.ts';
import type { ListDeploymentsRequest } from './dto.ts';

/**
 * Постраничный обход как асинхронный итератор: вызывающий пишет обычный
 * for await и не думает про offset.
 */
export async function* paginateDeployments(
  client: ShipyardClient,
  request: ListDeploymentsRequest = {},
  signal?: AbortSignal,
): AsyncGenerator<Deployment, void, void> {
  let offset = request.offset ?? 0;

  for (;;) {
    const page = await client.deployments({ ...request, offset }, signal);
    if (!page.ok) return;

    yield* page.value.items;

    const next = hasMore(page.value) ? nextOffset(page.value) : null;
    if (next === null || next === offset) return;

    offset = next;
  }
}

export async function collectDeployments(
  client: ShipyardClient,
  request: ListDeploymentsRequest = {},
  limit = 500,
  signal?: AbortSignal,
): Promise<readonly Deployment[]> {
  const collected: Deployment[] = [];

  for await (const deployment of paginateDeployments(client, request, signal)) {
    collected.push(deployment);
    if (collected.length >= limit) break;
  }

  return collected;
}
