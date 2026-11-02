import type { Deployment } from '#domain/deployment.ts';
import type { DeploymentId } from '#domain/ids.ts';
import type { DeploymentQuery } from '#domain/query.ts';
import { flatMapResult, mapResult, ok } from '#lib/result.ts';
import type { DeploymentSource } from '#services/ports.ts';

import type { HttpClient } from './client.ts';
import { toDeployment, toDeployments } from './mappers.ts';
import { parseWith } from './parser.ts';
import type { ApiResult, Page } from './response.ts';
import { pageOf } from './response.ts';
import { deploymentListSchema, deploymentSchema } from './schemas.ts';
import type { QueryParams } from './url.ts';

function toParams(query: DeploymentQuery): QueryParams {
  return {
    environment: query.environment,
    status: query.status,
    author: query.author,
    limit: query.limit,
    offset: query.offset,
  };
}

/** HTTP-реализация порта: сеть → схема → доменная модель. */
export class HttpDeploymentSource implements DeploymentSource {
  readonly #client: HttpClient;

  constructor(client: HttpClient) {
    this.#client = client;
  }

  async list(query: DeploymentQuery, signal?: AbortSignal): Promise<ApiResult<Page<Deployment>>> {
    const raw = await this.#client.getJson('/deployments', toParams(query), signal);

    return flatMapResult(raw, (payload) =>
      mapResult(parseWith(deploymentListSchema, payload), (dto) =>
        pageOf(toDeployments(dto.data), dto.meta),
      ),
    );
  }

  async byId(id: DeploymentId, signal?: AbortSignal): Promise<ApiResult<Deployment | null>> {
    const raw = await this.#client.getJson(`/deployments/${id}`, {}, signal);

    if (!raw.ok && raw.error.kind === 'http' && raw.error.status === 404) {
      return ok(null);
    }

    return flatMapResult(raw, (payload) =>
      mapResult(parseWith(deploymentSchema, payload), toDeployment),
    );
  }
}
