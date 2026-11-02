import { HttpClient } from '#api/client.ts';
import type { FetchLike } from '#api/client.ts';
import type { ApiError } from '#api/errors.ts';
import { toDeployment, toDeployments } from '#api/mappers.ts';
import { parseWith } from '#api/parser.ts';
import type { ApiResult, Page } from '#api/response.ts';
import { pageOf } from '#api/response.ts';
import type { QueryParams } from '#api/url.ts';
import type { Deployment } from '#domain/deployment.ts';
import { flatMapResult, mapResult, ok, unwrapOrThrow } from '#lib/result.ts';

import type { ListDeploymentsRequest, ListDeploymentsResponse } from './dto.ts';
import { toShipyardError } from './errors.ts';
import { toSummaryDtos } from './mappers.ts';
import { itemResponseSchema, listResponseSchema, summaryResponseSchema } from './schemas.ts';
import type { SummaryResponse } from './schemas.ts';

export interface ShipyardClientOptions {
  readonly baseUrl: string;
  readonly timeoutMs?: number;
  readonly retries?: number;
  readonly fetchImpl?: FetchLike;
}

function toParams(request: ListDeploymentsRequest): QueryParams {
  return {
    environment: request.environment,
    status: request.status,
    author: request.author,
    limit: request.limit,
    offset: request.offset,
  };
}

/**
 * Публичный клиент Shipyard: одинаково работает в браузере и в Node,
 * потому что зависит только от fetch и схем валидации.
 */
export class ShipyardClient {
  readonly #http: HttpClient;

  constructor(options: ShipyardClientOptions) {
    this.#http = new HttpClient({
      baseUrl: options.baseUrl,
      ...(options.timeoutMs === undefined ? {} : { timeoutMs: options.timeoutMs }),
      ...(options.retries === undefined ? {} : { retries: options.retries }),
      ...(options.fetchImpl === undefined ? {} : { fetchImpl: options.fetchImpl }),
    });
  }

  async deployments(
    request: ListDeploymentsRequest = {},
    signal?: AbortSignal,
  ): Promise<ApiResult<Page<Deployment>>> {
    const raw = await this.#http.getJson('/deployments', toParams(request), signal);

    return flatMapResult(raw, (payload) =>
      mapResult(parseWith(listResponseSchema, payload), (dto) =>
        pageOf(toDeployments(dto.data), dto.meta),
      ),
    );
  }

  /** Сокращённая форма ответа: то, что удобно показывать в списках. */
  async deploymentSummaries(
    request: ListDeploymentsRequest = {},
    signal?: AbortSignal,
  ): Promise<ApiResult<ListDeploymentsResponse>> {
    const page = await this.deployments(request, signal);

    return mapResult(page, (value) => ({
      items: toSummaryDtos(value.items),
      page: value.meta,
    }));
  }

  async deployment(id: string, signal?: AbortSignal): Promise<ApiResult<Deployment | null>> {
    const raw = await this.#http.getJson(`/deployments/${id}`, {}, signal);

    if (!raw.ok && raw.error.kind === 'http' && raw.error.status === 404) return ok(null);

    return flatMapResult(raw, (payload) =>
      mapResult(parseWith(itemResponseSchema, payload), toDeployment),
    );
  }

  async summary(
    request: ListDeploymentsRequest = {},
    signal?: AbortSignal,
  ): Promise<ApiResult<SummaryResponse>> {
    const raw = await this.#http.getJson('/summary', toParams(request), signal);
    return flatMapResult(raw, (payload) => parseWith(summaryResponseSchema, payload));
  }

  /** Вариант с исключениями для тех, кому Result неудобен. */
  async deploymentsOrThrow(
    request: ListDeploymentsRequest = {},
    signal?: AbortSignal,
  ): Promise<Page<Deployment>> {
    const result = await this.deployments(request, signal);
    return unwrapOrThrow(result, (error: ApiError) => toShipyardError(error).message);
  }
}
