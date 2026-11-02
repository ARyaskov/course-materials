import type { Result } from '#lib/result.ts';

import type { ApiError } from './errors.ts';

export type PageMeta = {
  readonly total: number;
  readonly limit: number;
  readonly offset: number;
};

/** Страница любых элементов: один обобщённый контейнер на весь проект. */
export interface Page<T> {
  readonly items: readonly T[];
  readonly meta: PageMeta | null;
}

/** Результат обращения к API: успех с данными либо разобранная ошибка. */
export type ApiResult<T> = Result<T, ApiError>;

export function emptyPage<T>(): Page<T> {
  return { items: [], meta: null };
}

export function pageOf<T>(items: readonly T[], meta: PageMeta | null = null): Page<T> {
  return { items, meta };
}

export function mapPage<T, R>(page: Page<T>, transform: (item: T) => R): Page<R> {
  return { items: page.items.map(transform), meta: page.meta };
}

export function hasMore(page: Page<unknown>): boolean {
  if (page.meta === null) return false;
  return page.meta.offset + page.items.length < page.meta.total;
}

export function nextOffset(page: Page<unknown>): number | null {
  if (!hasMore(page) || page.meta === null) return null;
  return page.meta.offset + page.items.length;
}
