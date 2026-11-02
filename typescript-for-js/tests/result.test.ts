import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { describeApiError, isRetryable, statusForApiError } from '#api/errors.ts';
import type { ApiError } from '#api/errors.ts';
import {
  err,
  flatMapResult,
  mapError,
  mapResult,
  ok,
  tryAsync,
  trySync,
  unwrapOr,
  unwrapOrThrow,
} from '#lib/result.ts';

describe('Result', () => {
  it('преобразует только успешное значение', () => {
    assert.deepEqual(mapResult(ok(2), (value) => value * 2), ok(4));
    assert.deepEqual(mapResult(err('нет'), (value: number) => value * 2), err('нет'));
  });

  it('склеивает цепочку вычислений', () => {
    const parse = (value: string) =>
      Number.isNaN(Number(value)) ? err('не число') : ok(Number(value));

    assert.deepEqual(flatMapResult(ok('21'), parse), ok(21));
    assert.deepEqual(flatMapResult(ok('нет'), parse), err('не число'));
  });

  it('подменяет ошибку и достаёт значение', () => {
    assert.deepEqual(mapError(err(404), (code) => `код ${code}`), err('код 404'));
    assert.equal(unwrapOr(err('нет'), 7), 7);
    assert.throws(() => unwrapOrThrow(err('нет'), (error) => error), /нет/);
  });

  it('оборачивает исключения', async () => {
    const failed = await tryAsync(() => Promise.reject(new Error('сеть')));
    assert.equal(failed.ok, false);

    const succeeded = trySync(() => 1 + 1);
    assert.deepEqual(succeeded, ok(2));
  });
});

describe('ApiError', () => {
  const cases: readonly ApiError[] = [
    { kind: 'network', message: 'ECONNRESET' },
    { kind: 'timeout', ms: 5000 },
    { kind: 'aborted' },
    { kind: 'http', status: 503, url: '/api/deployments' },
    { kind: 'invalid_json', message: 'Unexpected token' },
    { kind: 'invalid_shape', issues: ['data.0.status: неизвестный статус'] },
  ];

  it('описывает каждый вариант', () => {
    for (const error of cases) {
      assert.ok(describeApiError(error).length > 0);
    }
  });

  it('повторяет только случайные сбои', () => {
    assert.equal(isRetryable({ kind: 'timeout', ms: 1 }), true);
    assert.equal(isRetryable({ kind: 'http', status: 500, url: '/x' }), true);
    assert.equal(isRetryable({ kind: 'http', status: 404, url: '/x' }), false);
    assert.equal(isRetryable({ kind: 'invalid_shape', issues: [] }), false);
  });

  it('переводит ошибку в код ответа', () => {
    assert.equal(statusForApiError({ kind: 'http', status: 404, url: '/x' }), 404);
    assert.equal(statusForApiError({ kind: 'timeout', ms: 1 }), 504);
    assert.equal(statusForApiError({ kind: 'invalid_shape', issues: [] }), 502);
  });
});
