import type { ListDeploymentsRequest } from '#sdk/dto.ts';

import type { BoardFilters } from './board-state.ts';

/** Пустые фильтры не должны превращаться в пустые query-параметры. */
export function requestFromFilters(filters: BoardFilters, limit: number): ListDeploymentsRequest {
  return {
    ...(filters.environment === null ? {} : { environment: filters.environment }),
    ...(filters.status === null ? {} : { status: filters.status }),
    ...(filters.author === '' ? {} : { author: filters.author }),
    limit,
  };
}

export function describeFilters(filters: BoardFilters): string {
  const parts = [
    filters.environment === null ? null : `окружение: ${filters.environment}`,
    filters.status === null ? null : `статус: ${filters.status}`,
    filters.author === '' ? null : `автор: ${filters.author}`,
  ].filter((part) => part !== null);

  return parts.length === 0 ? 'без фильтров' : parts.join(', ');
}
