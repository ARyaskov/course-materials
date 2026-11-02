import { delay } from '#lib/delay.ts';
import { readJsonResponse } from '#lib/json.ts';
import { err, ok } from '#lib/result.ts';

import {
  abortedError,
  httpError,
  invalidJsonError,
  isRetryable,
  networkError,
  timeoutError,
} from './errors.ts';
import type { ApiError } from './errors.ts';
import type { ApiResult } from './response.ts';
import { buildUrl } from './url.ts';
import type { QueryParams } from './url.ts';

/** Минимальный контракт fetch: в тестах вместо сети подставляется функция. */
export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export interface HttpClientOptions {
  readonly baseUrl: string;
  readonly timeoutMs?: number;
  readonly retries?: number;
  readonly headers?: Readonly<Record<string, string>>;
  readonly fetchImpl?: FetchLike;
}

export class HttpClient {
  readonly #baseUrl: string;
  readonly #timeoutMs: number;
  readonly #retries: number;
  readonly #headers: Readonly<Record<string, string>>;
  readonly #fetch: FetchLike;

  constructor(options: HttpClientOptions) {
    this.#baseUrl = options.baseUrl;
    this.#timeoutMs = options.timeoutMs ?? 5000;
    this.#retries = Math.max(options.retries ?? 2, 0);
    this.#headers = options.headers ?? { accept: 'application/json' };
    this.#fetch = options.fetchImpl ?? ((input, init) => fetch(input, init));
  }

  get baseUrl(): string {
    return this.#baseUrl;
  }

  /** Возвращает разобранный JSON как unknown: проверка схемой — шаг вызывающего. */
  async getJson(
    path: string,
    params: QueryParams = {},
    signal?: AbortSignal,
  ): Promise<ApiResult<unknown>> {
    const url = buildUrl(this.#baseUrl, path, params);
    let lastError: ApiError = networkError('запрос не выполнялся');

    for (let attempt = 0; attempt <= this.#retries; attempt += 1) {
      const result = await this.#requestOnce(url, signal);
      if (result.ok) return result;

      lastError = result.error;
      if (!isRetryable(result.error)) return result;

      if (attempt < this.#retries) {
        await delay(150 * (attempt + 1), signal);
      }
    }

    return err(lastError);
  }

  async #requestOnce(url: string, signal?: AbortSignal): Promise<ApiResult<unknown>> {
    const timeout = AbortSignal.timeout(this.#timeoutMs);
    const combined = signal === undefined ? timeout : AbortSignal.any([signal, timeout]);

    let response: Response;
    try {
      response = await this.#fetch(url, { headers: { ...this.#headers }, signal: combined });
    } catch (caught) {
      return err(this.#toTransportError(caught, timeout, signal));
    }

    if (!response.ok) return err(httpError(response.status, url));

    try {
      return ok(await readJsonResponse(response));
    } catch (caught) {
      return err(invalidJsonError(caught instanceof Error ? caught.message : String(caught)));
    }
  }

  #toTransportError(caught: unknown, timeout: AbortSignal, signal?: AbortSignal): ApiError {
    if (timeout.aborted) return timeoutError(this.#timeoutMs);
    if (signal?.aborted === true) return abortedError();
    return networkError(caught instanceof Error ? caught.message : String(caught));
  }
}
