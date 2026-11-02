import type { FetchLike } from '#api/client.ts';
import type { ApiResult, Page } from '#api/response.ts';
import { pageOf } from '#api/response.ts';
import type { Deployment } from '#domain/deployment.ts';
import type { DeploymentId } from '#domain/ids.ts';
import type { DeploymentQuery } from '#domain/query.ts';
import { applyQuery } from '#domain/query.ts';
import { err, ok } from '#lib/result.ts';
import type { ApiError } from '#api/errors.ts';
import type { DeploymentSource } from '#services/ports.ts';

/** Ответ, который подставляется вместо сети. */
export interface StubResponse {
  readonly status?: number;
  readonly body?: unknown;
  readonly rawBody?: string;
  readonly fail?: Error;
}

export interface RecordedRequest {
  readonly url: string;
  readonly init: RequestInit | undefined;
}

export interface FetchStub {
  readonly fetch: FetchLike;
  readonly calls: readonly RecordedRequest[];
}

/** Заглушка fetch: отдаёт заранее подготовленные ответы по очереди. */
export function stubFetch(responses: readonly StubResponse[]): FetchStub {
  const calls: RecordedRequest[] = [];
  let index = 0;

  const fetchImpl: FetchLike = (url, init) => {
    calls.push({ url, init });

    const response = responses[Math.min(index, responses.length - 1)];
    index += 1;

    if (response === undefined) return Promise.reject(new Error('нет заготовленного ответа'));
    if (response.fail !== undefined) return Promise.reject(response.fail);

    const body = response.rawBody ?? JSON.stringify(response.body ?? {});

    return Promise.resolve(
      new Response(body, {
        status: response.status ?? 200,
        headers: { 'content-type': 'application/json' },
      }),
    );
  };

  return { fetch: fetchImpl, calls };
}

/** Источник данных для тестов сервисного слоя. */
export class StubSource implements DeploymentSource {
  #deployments: readonly Deployment[];
  #error: ApiError | null;
  listCalls = 0;

  constructor(deployments: readonly Deployment[], error: ApiError | null = null) {
    this.#deployments = deployments;
    this.#error = error;
  }

  list(query: DeploymentQuery): Promise<ApiResult<Page<Deployment>>> {
    this.listCalls += 1;
    if (this.#error !== null) return Promise.resolve(err(this.#error));

    const items = applyQuery(this.#deployments, query);
    return Promise.resolve(
      ok(pageOf(items, { total: this.#deployments.length, limit: query.limit, offset: 0 })),
    );
  }

  byId(id: DeploymentId): Promise<ApiResult<Deployment | null>> {
    if (this.#error !== null) return Promise.resolve(err(this.#error));
    return Promise.resolve(ok(this.#deployments.find((item) => item.id === id) ?? null));
  }
}
