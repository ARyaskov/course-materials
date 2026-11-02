import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { fixtureDeployments } from '#fixtures/deployments.ts';
import { renderReport, toReportJson, toRows } from '#reports/report.ts';
import { orderedStatuses, summarize } from '#reports/summary.ts';

describe('summarize', () => {
  const summary = summarize(fixtureDeployments);

  it('учитывает все деплои', () => {
    assert.equal(summary.total, fixtureDeployments.length);

    const counted = Object.values(summary.byStatus).reduce((sum, value) => sum + value, 0);
    assert.equal(counted, fixtureDeployments.length);
  });

  it('считает долю успеха только по завершённым', () => {
    const production = summary.environments.find((item) => item.environment === 'production');
    assert.ok(production !== undefined);

    // production: succeeded, failed, rolled_back, queued -> 1 из 3 завершённых
    assert.equal(production.total, 4);
    assert.ok(Math.abs(production.successRate - 1 / 3) < 1e-9);
  });

  it('оставляет пустое окружение без деления на ноль', () => {
    const empty = summarize([]);
    assert.equal(empty.successRate, 0);
    assert.equal(empty.environments.every((item) => item.total === 0), true);
    assert.equal(empty.environments[0]?.averageDurationMs, null);
  });

  it('собирает список падений', () => {
    assert.equal(summary.failures.length, 2);
    assert.equal(summary.failures.every((item) => item.status === 'failed'), true);
  });

  it('перечисляет статусы в фиксированном порядке', () => {
    const statuses = orderedStatuses(summary.byStatus).map(([status]) => status);
    assert.deepEqual(statuses, ['queued', 'running', 'succeeded', 'failed', 'rolled_back']);
  });
});

describe('отчёт', () => {
  const summary = summarize(fixtureDeployments);

  it('в тексте есть окружения и падения', () => {
    const text = renderReport(summary);

    assert.match(text, /Shipyard/);
    assert.match(text, /production/);
    assert.match(text, /dep_002/);
  });

  it('строки таблицы заполнены для всех статусов', () => {
    const rows = toRows(fixtureDeployments);

    assert.equal(rows.length, fixtureDeployments.length);
    assert.equal(rows.every((row) => row.duration.length > 0), true);

    const queued = rows.find((row) => row.id === 'dep_009');
    assert.equal(queued?.duration, '—');
  });

  it('JSON повторяет содержимое текста', () => {
    const json = toReportJson(summary);

    assert.equal(typeof json, 'object');
    assert.ok(typeof json === 'object' && json !== null && 'environments' in json);
  });
});
