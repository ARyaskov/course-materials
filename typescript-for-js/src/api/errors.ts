import { assertNever } from '#lib/assert-never.ts';

/** Всё, что может пойти не так на границе с внешним API. */
export type ApiError =
  | { readonly kind: 'network'; readonly message: string }
  | { readonly kind: 'timeout'; readonly ms: number }
  | { readonly kind: 'aborted' }
  | { readonly kind: 'http'; readonly status: number; readonly url: string }
  | { readonly kind: 'invalid_json'; readonly message: string }
  | { readonly kind: 'invalid_shape'; readonly issues: readonly string[] };

export const networkError = (message: string): ApiError => ({ kind: 'network', message });
export const timeoutError = (ms: number): ApiError => ({ kind: 'timeout', ms });
export const abortedError = (): ApiError => ({ kind: 'aborted' });
export const httpError = (status: number, url: string): ApiError => ({ kind: 'http', status, url });
export const invalidJsonError = (message: string): ApiError => ({ kind: 'invalid_json', message });
export const invalidShapeError = (issues: readonly string[]): ApiError => ({
  kind: 'invalid_shape',
  issues,
});

export function describeApiError(error: ApiError): string {
  switch (error.kind) {
    case 'network':
      return `Сеть недоступна: ${error.message}`;
    case 'timeout':
      return `Запрос не уложился в ${error.ms} мс`;
    case 'aborted':
      return 'Запрос отменён';
    case 'http':
      return `Сервер ответил ${error.status} на ${error.url}`;
    case 'invalid_json':
      return `Ответ не является JSON: ${error.message}`;
    case 'invalid_shape':
      return `Ответ не соответствует схеме:\n  ${error.issues.join('\n  ')}`;
    default:
      return assertNever(error, 'describeApiError');
  }
}

/** Повторять имеет смысл только то, что могло сломаться случайно. */
export function isRetryable(error: ApiError): boolean {
  switch (error.kind) {
    case 'network':
    case 'timeout':
      return true;
    case 'http':
      return error.status >= 500 || error.status === 429;
    case 'aborted':
    case 'invalid_json':
    case 'invalid_shape':
      return false;
    default:
      return assertNever(error, 'isRetryable');
  }
}

/** Код ответа, который стоит вернуть наружу, если ошибка дошла до HTTP-слоя. */
export function statusForApiError(error: ApiError): number {
  switch (error.kind) {
    case 'http':
      return error.status === 404 ? 404 : 502;
    case 'timeout':
      return 504;
    case 'aborted':
      return 499;
    case 'network':
    case 'invalid_json':
    case 'invalid_shape':
      return 502;
    default:
      return assertNever(error, 'statusForApiError');
  }
}
