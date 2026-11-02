import type { ApiError } from '#api/errors.ts';
import type { ApiResult, Page, PageMeta } from '#api/response.ts';
import type { Deployment } from '#domain/deployment.ts';
import type { DeploymentId } from '#domain/ids.ts';
import { toDeploymentId } from '#domain/ids.ts';
import type { DeploymentQuery } from '#domain/query.ts';
import { EMPTY_QUERY } from '#domain/query.ts';
import { compareVersionStrings } from '#domain/version.ts';
import { err, mapResult, ok } from '#lib/result.ts';
import type { DeploymentSummary } from '#reports/summary.ts';
import { summarize } from '#reports/summary.ts';

import type { DeploymentSource, Logger } from './ports.ts';

export interface Board {
  readonly deployments: readonly Deployment[];
  readonly summary: DeploymentSummary;
  readonly meta: PageMeta | null;
}

export interface DeploymentServiceOptions {
  readonly source: DeploymentSource;
  readonly logger?: Logger;
}

/**
 * Прикладной слой: знает про домен и порты, но ничего не знает про HTTP,
 * консоль и DOM. Ошибки не выбрасываются, а возвращаются в Result.
 */
export class DeploymentService {
  readonly #source: DeploymentSource;
  readonly #logger: Logger | null;

  constructor(options: DeploymentServiceOptions) {
    this.#source = options.source;
    this.#logger = options.logger ?? null;
  }

  async board(
    query: DeploymentQuery = EMPTY_QUERY,
    signal?: AbortSignal,
  ): Promise<ApiResult<Board>> {
    const page = await this.#source.list(query, signal);

    if (!page.ok) {
      this.#logger?.log('warn', 'Не удалось получить список деплоев', page.error);
      return page;
    }

    return ok(this.#toBoard(page.value));
  }

  async find(id: string, signal?: AbortSignal): Promise<ApiResult<Deployment | null>> {
    const deploymentId = toDeploymentId(id);

    if (deploymentId === null) {
      const error: ApiError = {
        kind: 'invalid_shape',
        issues: [`id: ожидался идентификатор вида dep_1a2b, получено ${id}`],
      };
      return err(error);
    }

    return this.#source.byId(deploymentId, signal);
  }

  async summary(
    query: DeploymentQuery = EMPTY_QUERY,
    signal?: AbortSignal,
  ): Promise<ApiResult<DeploymentSummary>> {
    const board = await this.board(query, signal);
    return mapResult(board, (value) => value.summary);
  }

  /** Последний по времени деплой в каждом окружении. */
  async latestVersions(
    query: DeploymentQuery = EMPTY_QUERY,
    signal?: AbortSignal,
  ): Promise<ApiResult<readonly Deployment[]>> {
    const board = await this.board(query, signal);

    return mapResult(board, (value) =>
      value.deployments
        .filter((deployment) => deployment.status === 'succeeded')
        .toSorted((left, right) =>
          compareVersionStrings(right.release.version, left.release.version),
        ),
    );
  }

  async byIdStrict(id: DeploymentId, signal?: AbortSignal): Promise<ApiResult<Deployment | null>> {
    return this.#source.byId(id, signal);
  }

  #toBoard(page: Page<Deployment>): Board {
    return {
      deployments: page.items,
      summary: summarize(page.items),
      meta: page.meta,
    };
  }
}
