import { describeApiError, statusForApiError } from '#api/errors.ts';
import { fromDeployment } from '#api/mappers.ts';
import { EMPTY_QUERY } from '#domain/query.ts';
import type { DeploymentQuery } from '#domain/query.ts';
import { isDeploymentStatus } from '#domain/deployment-status.ts';
import { isEnvironment } from '#domain/environment.ts';
import { DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE } from '#domain/constants.ts';
import type { JsonValue } from '#lib/json.ts';
import { clamp, toFiniteNumber, toPositiveInt } from '#lib/number.ts';
import type { DeploymentService } from '#services/deployment-service.ts';
import { toReportJson } from '#reports/report.ts';

import { sendError, sendJson } from '../respond.ts';
import type { RouteHandler } from '../router.ts';

/** Query string — это всегда строки: превращаем их в типизированный запрос. */
export function queryFromSearchParams(params: URLSearchParams): DeploymentQuery {
  const environment = params.get('environment');
  const status = params.get('status');
  const limit = toPositiveInt(params.get('limit'));
  const offset = toFiniteNumber(params.get('offset'));

  return {
    ...EMPTY_QUERY,
    environment: environment !== null && isEnvironment(environment) ? environment : null,
    status: status !== null && isDeploymentStatus(status) ? status : null,
    author: params.get('author'),
    limit: limit === null ? DEFAULT_PAGE_SIZE : clamp(limit, 1, MAX_PAGE_SIZE),
    offset: offset === null || offset < 0 ? 0 : Math.floor(offset),
  };
}

export function listDeployments(service: DeploymentService): RouteHandler {
  return async ({ url, response }) => {
    const query = queryFromSearchParams(url.searchParams);
    const board = await service.board(query);

    if (!board.ok) {
      sendError(response, statusForApiError(board.error), describeApiError(board.error));
      return;
    }

    const payload: JsonValue = {
      data: board.value.deployments.map(fromDeployment),
      meta: board.value.meta,
    };

    sendJson(response, 200, payload);
  };
}

export function getDeployment(service: DeploymentService): RouteHandler {
  return async ({ params, response }) => {
    const id = params['id'] ?? '';
    const found = await service.find(id);

    if (!found.ok) {
      sendError(response, statusForApiError(found.error), describeApiError(found.error));
      return;
    }

    if (found.value === null) {
      sendError(response, 404, `Деплой ${id} не найден`);
      return;
    }

    sendJson(response, 200, fromDeployment(found.value));
  };
}

export function getSummary(service: DeploymentService): RouteHandler {
  return async ({ url, response }) => {
    const summary = await service.summary(queryFromSearchParams(url.searchParams));

    if (!summary.ok) {
      sendError(response, statusForApiError(summary.error), describeApiError(summary.error));
      return;
    }

    sendJson(response, 200, toReportJson(summary.value));
  };
}

export function healthCheck(): RouteHandler {
  return ({ response }) => {
    sendJson(response, 200, { status: 'ok', time: new Date().toISOString() });
  };
}
