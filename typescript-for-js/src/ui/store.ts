import type { BoardAction, BoardState } from './board-state.ts';
import { boardReducer, initialBoardState } from './board-state.ts';

export type Listener<S> = (state: S) => void;
export type Unsubscribe = () => void;

/** Минимальное хранилище: редьюсер, текущее состояние и подписчики. */
export class Store<S, A> {
  #state: S;
  readonly #reducer: (state: S, action: A) => S;
  readonly #listeners = new Set<Listener<S>>();

  constructor(reducer: (state: S, action: A) => S, initial: S) {
    this.#reducer = reducer;
    this.#state = initial;
  }

  get state(): S {
    return this.#state;
  }

  dispatch(action: A): void {
    const next = this.#reducer(this.#state, action);
    if (next === this.#state) return;

    this.#state = next;
    for (const listener of this.#listeners) listener(next);
  }

  subscribe(listener: Listener<S>): Unsubscribe {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }
}

export type BoardStore = Store<BoardState, BoardAction>;

export function createBoardStore(initial: BoardState = initialBoardState): BoardStore {
  return new Store(boardReducer, initial);
}
