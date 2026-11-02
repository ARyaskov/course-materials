import { ShipyardClient } from '#sdk/index.ts';

import { bindBoard, bindForm } from './events.ts';
import { filtersFromForm } from './form.ts';
import { loadBoard } from './load.ts';
import { renderBoard } from './render.ts';
import { requireElement } from './dom.ts';
import { createBoardStore } from './store.ts';

const API_BASE_URL = `${globalThis.location.origin}/api`;

function start(): void {
  const form = requireElement('#filters', HTMLFormElement);
  const board = requireElement('#board', HTMLElement);

  const store = createBoardStore();
  const client = new ShipyardClient({ baseUrl: API_BASE_URL, timeoutMs: 8000 });

  let inflight: AbortController | null = null;

  const reload = (): void => {
    inflight?.abort();
    inflight = new AbortController();

    void loadBoard(store, client, store.state.filters, { signal: inflight.signal, limit: 50 });
  };

  store.subscribe((state) => {
    renderBoard(board, state);
  });

  bindForm({ form, board, store, reload });
  bindBoard({ form, board, store, reload });

  store.dispatch({ type: 'filters', patch: filtersFromForm(form) });
  reload();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', start, { once: true });
} else {
  start();
}
