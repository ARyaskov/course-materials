import type { Deployment } from '#domain/deployment.ts';
import type { DeploymentId } from '#domain/ids.ts';
import type { DeploymentQuery } from '#domain/query.ts';
import { MemoryCache } from '#lib/memory-cache.ts';
import { ok } from '#lib/result.ts';
import type { Cache, DeploymentSource } from '#services/ports.ts';

import type { ApiResult, Page } from './response.ts';

function queryKey(query: DeploymentQuery): string {
  return [query.environment ?? '*', query.status ?? '*', query.author ?? '*', query.limit].join('|');
}

/**
 * Декоратор источника: тот же интерфейс снаружи, кеш внутри.
 * Кешируются только успешные ответы — ошибку повторять смысла нет.
 */
export class CachedDeploymentSource implements DeploymentSource {
  readonly #inner: DeploymentSource;
  readonly #pages: Cache<Page<Deployment>>;
  readonly #items: Cache<Deployment | null>;

  constructor(inner: DeploymentSource, ttlMs = 30_000) {
    this.#inner = inner;
    this.#pages = new MemoryCache<Page<Deployment>>(ttlMs);
    this.#items = new MemoryCache<Deployment | null>(ttlMs);
  }

  async list(query: DeploymentQuery, signal?: AbortSignal): Promise<ApiResult<Page<Deployment>>> {
    const key = queryKey(query);
    const cached = this.#pages.get(key);
    if (cached !== null) return ok(cached);

    const result = await this.#inner.list(query, signal);
    if (result.ok) this.#pages.set(key, result.value);

    return result;
  }

  async byId(id: DeploymentId, signal?: AbortSignal): Promise<ApiResult<Deployment | null>> {
    const cached = this.#items.get(id);
    if (cached !== null) return ok(cached);

    const result = await this.#inner.byId(id, signal);
    if (result.ok) this.#items.set(id, result.value);

    return result;
  }

  invalidate(): void {
    this.#pages.clear();
    this.#items.clear();
  }
}
