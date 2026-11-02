import type { ApiResult, Page } from '#api/response.ts';
import type { Deployment } from '#domain/deployment.ts';
import type { DeploymentId } from '#domain/ids.ts';
import type { DeploymentQuery } from '#domain/query.ts';

/**
 * Порт источника данных. Сервисный слой знает только этот интерфейс,
 * поэтому HTTP, фикстуры и кеш подставляются без изменений в бизнес-логике.
 */
export interface DeploymentSource {
  list(query: DeploymentQuery, signal?: AbortSignal): Promise<ApiResult<Page<Deployment>>>;
  byId(id: DeploymentId, signal?: AbortSignal): Promise<ApiResult<Deployment | null>>;
}

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export interface Logger {
  log(level: LogLevel, message: string, details?: unknown): void;
}

/** Кеш с типизированным значением: ключ — строка, значение — то, что положили. */
export interface Cache<T> {
  get(key: string): T | null;
  set(key: string, value: T): void;
  delete(key: string): void;
  clear(): void;
}
