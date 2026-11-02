import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { formatCount, formatDateTime, formatDuration, formatPercent } from '#lib/format.ts';
import { average, clamp, percentile, toFiniteNumber, toPositiveInt } from '#lib/number.ts';

describe('formatDuration', () => {
  it('показывает прочерк вместо отсутствующего значения', () => {
    assert.equal(formatDuration(null), '—');
    assert.equal(formatDuration(Number.NaN), '—');
    assert.equal(formatDuration(-1), '—');
  });

  it('выбирает единицы по величине', () => {
    assert.equal(formatDuration(420), '420 мс');
    assert.equal(formatDuration(45_000), '45 с');
    assert.equal(formatDuration(402_000), '6 мин 42 с');
    assert.equal(formatDuration(3_930_000), '1 ч 5 мин');
  });
});

describe('formatCount', () => {
  const forms = ['деплой', 'деплоя', 'деплоев'] as const;

  it('склоняет существительное', () => {
    assert.equal(formatCount(1, forms), '1 деплой');
    assert.equal(formatCount(3, forms), '3 деплоя');
    assert.equal(formatCount(5, forms), '5 деплоев');
    assert.equal(formatCount(11, forms), '11 деплоев');
    assert.equal(formatCount(21, forms), '21 деплой');
  });
});

describe('formatPercent и formatDateTime', () => {
  it('форматирует долю', () => {
    assert.equal(formatPercent(0.625), '62.5%');
    assert.equal(formatPercent(1, 0), '100%');
  });

  it('оставляет исходную строку, если это не дата', () => {
    assert.equal(formatDateTime('вчера'), 'вчера');
    assert.equal(formatDateTime(null), '—');
    assert.equal(formatDateTime('2026-08-28T09:12:00.000Z'), '2026-08-28 09:12');
  });
});

describe('числовые помощники', () => {
  it('превращает мусор в null, а не в NaN', () => {
    assert.equal(toFiniteNumber('12'), 12);
    assert.equal(toFiniteNumber(' '), null);
    assert.equal(toFiniteNumber('abc'), null);
    assert.equal(toFiniteNumber(Number.POSITIVE_INFINITY), null);
    assert.equal(toPositiveInt('0'), null);
    assert.equal(toPositiveInt('7'), 7);
  });

  it('считает среднее и перцентиль', () => {
    assert.equal(average([]), null);
    assert.equal(average([2, 4]), 3);
    assert.equal(percentile([1, 2, 3, 4, 5], 0.95), 5);
    assert.equal(percentile([], 0.5), null);
    assert.equal(clamp(15, 1, 10), 10);
  });
});
