import type { BoardStore } from './store.ts';
import { filtersFromForm } from './form.ts';

export type Unbind = () => void;

/**
 * Типы событий берутся из HTMLElementEventMap, поэтому в обработчике
 * сразу известен конкретный тип события.
 */
export function on<K extends keyof HTMLElementEventMap>(
  target: HTMLElement,
  type: K,
  handler: (event: HTMLElementEventMap[K]) => void,
  options?: AddEventListenerOptions,
): Unbind {
  target.addEventListener(type, handler, options);
  return () => target.removeEventListener(type, handler, options);
}

export interface BindOptions {
  readonly form: HTMLFormElement;
  readonly board: HTMLElement;
  readonly store: BoardStore;
  readonly reload: () => void;
}

export function bindForm(options: BindOptions): Unbind {
  const unbindSubmit = on(options.form, 'submit', (event) => {
    event.preventDefault();
    options.store.dispatch({ type: 'filters', patch: filtersFromForm(options.form) });
    options.reload();
  });

  const unbindReset = on(options.form, 'reset', () => {
    // reset срабатывает до очистки полей, поэтому переносим чтение на следующий тик.
    queueMicrotask(() => {
      options.store.dispatch({ type: 'filters', patch: filtersFromForm(options.form) });
      options.reload();
    });
  });

  return () => {
    unbindSubmit();
    unbindReset();
  };
}

/** Одно делегированное событие на весь список карточек вместо N обработчиков. */
export function bindBoard(options: BindOptions): Unbind {
  return on(options.board, 'click', (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const card = target.closest('.card');
    if (!(card instanceof HTMLElement)) return;

    const id = card.dataset['id'];
    if (id === undefined) return;

    const current = options.store.state.selectedId;
    options.store.dispatch({ type: 'select', id: current === id ? null : id });
  });
}
