import { describeApiError } from '#api/errors.ts';
import type { ApiError } from '#api/errors.ts';

/**
 * Наружу SDK отдаёт Result, но тем, кто предпочитает исключения,
 * даёт готовый класс ошибки с сохранённой причиной.
 */
export class ShipyardError extends Error {
  readonly apiError: ApiError;

  constructor(apiError: ApiError) {
    super(describeApiError(apiError));
    this.name = 'ShipyardError';
    this.apiError = apiError;
  }

  get kind(): ApiError['kind'] {
    return this.apiError.kind;
  }
}

export function toShipyardError(error: ApiError): ShipyardError {
  return new ShipyardError(error);
}
