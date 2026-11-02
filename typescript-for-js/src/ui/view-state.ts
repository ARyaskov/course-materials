/** Состояние загрузки данных: четыре варианта вместо трёх булевых флагов. */
export type ViewState<T> =
  | { readonly kind: 'idle' }
  | { readonly kind: 'loading' }
  | { readonly kind: 'ready'; readonly data: T }
  | { readonly kind: 'error'; readonly message: string };

export const idle = (): ViewState<never> => ({ kind: 'idle' });
export const loading = (): ViewState<never> => ({ kind: 'loading' });
export const ready = <T>(data: T): ViewState<T> => ({ kind: 'ready', data });
export const failed = (message: string): ViewState<never> => ({ kind: 'error', message });

export function isReady<T>(state: ViewState<T>): state is { kind: 'ready'; data: T } {
  return state.kind === 'ready';
}

export function dataOf<T>(state: ViewState<T>): T | null {
  return state.kind === 'ready' ? state.data : null;
}

export function mapViewState<T, R>(state: ViewState<T>, transform: (data: T) => R): ViewState<R> {
  return state.kind === 'ready' ? ready(transform(state.data)) : state;
}
