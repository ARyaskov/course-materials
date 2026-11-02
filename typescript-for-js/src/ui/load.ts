import { describeApiError } from '#api/errors.ts';
import { summarize } from '#reports/summary.ts';
import type { ShipyardClient } from '#sdk/index.ts';

import type { BoardFilters } from './board-state.ts';
import { requestFromFilters } from './filters.ts';
import type { BoardStore } from './store.ts';

export interface LoadOptions {
  readonly limit?: number;
  readonly signal?: AbortSignal;
}

/**
 * Единственное место, где UI ходит в сеть: результат превращается
 * в действие хранилища, а не в исключение.
 */
export async function loadBoard(
  store: BoardStore,
  client: ShipyardClient,
  filters: BoardFilters,
  options: LoadOptions = {},
): Promise<void> {
  store.dispatch({ type: 'load' });

  const page = await client.deployments(
    requestFromFilters(filters, options.limit ?? 50),
    options.signal,
  );

  if (!page.ok) {
    store.dispatch({ type: 'failed', message: describeApiError(page.error) });
    return;
  }

  store.dispatch({
    type: 'loaded',
    data: { deployments: page.value.items, summary: summarize(page.value.items) },
  });
}
