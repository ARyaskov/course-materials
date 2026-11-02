import type { Deployment } from '#domain/deployment.ts';
import type { DeploymentId } from '#domain/ids.ts';
import type { DeploymentQuery } from '#domain/query.ts';
import { applyQuery } from '#domain/query.ts';
import { fixtureDeployments } from '#fixtures/deployments.ts';
import { delay } from '#lib/delay.ts';
import { ok } from '#lib/result.ts';
import type { DeploymentSource } from '#services/ports.ts';

import type { ApiResult, Page } from './response.ts';
import { pageOf } from './response.ts';

export interface FixtureSourceOptions {
  readonly deployments?: readonly Deployment[];
  /** Небольшая задержка делает поведение похожим на сеть. */
  readonly latencyMs?: number;
}

/** Источник данных без сети: тот же порт, что и у HTTP-версии. */
export class FixtureDeploymentSource implements DeploymentSource {
  readonly #deployments: readonly Deployment[];
  readonly #latencyMs: number;

  constructor(options: FixtureSourceOptions = {}) {
    this.#deployments = options.deployments ?? fixtureDeployments;
    this.#latencyMs = options.latencyMs ?? 0;
  }

  async list(query: DeploymentQuery, signal?: AbortSignal): Promise<ApiResult<Page<Deployment>>> {
    await this.#pause(signal);

    const matched = applyQuery(this.#deployments, {
      ...query,
      offset: 0,
      limit: Number.MAX_SAFE_INTEGER,
    });

    const items = matched.slice(query.offset, query.offset + query.limit);

    return ok(pageOf(items, { total: matched.length, limit: query.limit, offset: query.offset }));
  }

  async byId(id: DeploymentId, signal?: AbortSignal): Promise<ApiResult<Deployment | null>> {
    await this.#pause(signal);
    return ok(this.#deployments.find((deployment) => deployment.id === id) ?? null);
  }

  async #pause(signal?: AbortSignal): Promise<void> {
    if (this.#latencyMs > 0) await delay(this.#latencyMs, signal);
  }
}
