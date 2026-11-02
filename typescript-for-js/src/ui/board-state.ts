import type { Deployment } from '#domain/deployment.ts';
import type { DeploymentStatus } from '#domain/deployment-status.ts';
import type { Environment } from '#domain/environment.ts';
import { assertNever } from '#lib/assert-never.ts';
import type { DeploymentSummary } from '#reports/summary.ts';

import type { ViewState } from './view-state.ts';
import { failed, idle, loading, ready } from './view-state.ts';

export interface BoardData {
  readonly deployments: readonly Deployment[];
  readonly summary: DeploymentSummary;
}

export interface BoardFilters {
  readonly environment: Environment | null;
  readonly status: DeploymentStatus | null;
  readonly author: string;
}

export interface BoardState {
  readonly view: ViewState<BoardData>;
  readonly filters: BoardFilters;
  readonly selectedId: string | null;
}

export type BoardAction =
  | { readonly type: 'load' }
  | { readonly type: 'loaded'; readonly data: BoardData }
  | { readonly type: 'failed'; readonly message: string }
  | { readonly type: 'filters'; readonly patch: Partial<BoardFilters> }
  | { readonly type: 'select'; readonly id: string | null }
  | { readonly type: 'reset' };

export const EMPTY_FILTERS: BoardFilters = {
  environment: null,
  status: null,
  author: '',
};

export const initialBoardState: BoardState = {
  view: idle(),
  filters: EMPTY_FILTERS,
  selectedId: null,
};

/** Чистая функция: состояние меняется только здесь, поэтому его легко тестировать. */
export function boardReducer(state: BoardState, action: BoardAction): BoardState {
  switch (action.type) {
    case 'load':
      return { ...state, view: loading() };

    case 'loaded':
      return { ...state, view: ready(action.data) };

    case 'failed':
      return { ...state, view: failed(action.message) };

    case 'filters':
      return { ...state, filters: { ...state.filters, ...action.patch }, selectedId: null };

    case 'select':
      return { ...state, selectedId: action.id };

    case 'reset':
      return initialBoardState;

    default:
      return assertNever(action, 'boardReducer');
  }
}

export function selectedDeployment(state: BoardState): Deployment | null {
  if (state.view.kind !== 'ready' || state.selectedId === null) return null;
  return state.view.data.deployments.find((item) => item.id === state.selectedId) ?? null;
}
