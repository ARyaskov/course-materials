import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { CachedDeploymentSource } from '#api/cached-source.ts';
import { FixtureDeploymentSource } from '#api/fixture-source.ts';
import { EMPTY_QUERY } from '#domain/query.ts';
import { fixtureDeployments } from '#fixtures/deployments.ts';
import { DeploymentService } from '#services/deployment-service.ts';

import { StubSource } from './doubles.ts';

describe('DeploymentService', () => {
  it('собирает доску со сводкой', async () => {
    const service = new DeploymentService({ source: new FixtureDeploymentSource() });
    const board = await service.board();

    assert.equal(board.ok, true);
    if (!board.ok) return;

    assert.equal(board.value.deployments.length, fixtureDeployments.length);
    assert.equal(board.value.summary.total, fixtureDeployments.length);
    assert.equal(board.value.summary.environments.length, 3);
  });

  it('фильтрует по окружению и статусу', async () => {
    const service = new DeploymentService({ source: new FixtureDeploymentSource() });

    const board = await service.board({
      ...EMPTY_QUERY,
      environment: 'production',
      status: 'failed',
    });

    assert.equal(board.ok, true);
    if (!board.ok) return;

    assert.equal(board.value.deployments.length, 1);
    assert.equal(board.value.deployments[0]?.id, 'dep_002');
  });

  it('отклоняет некорректный идентификатор до запроса к источнику', async () => {
    const source = new StubSource(fixtureDeployments);
    const service = new DeploymentService({ source });

    const found = await service.find('42');

    assert.equal(found.ok, false);
    if (found.ok) return;
    assert.equal(found.error.kind, 'invalid_shape');
  });

  it('находит деплой по идентификатору', async () => {
    const service = new DeploymentService({ source: new FixtureDeploymentSource() });
    const found = await service.find('dep_004');

    assert.equal(found.ok, true);
    if (!found.ok) return;
    assert.equal(found.value?.environment, 'staging');
  });

  it('передаёт ошибку источника наружу', async () => {
    const source = new StubSource([], { kind: 'timeout', ms: 100 });
    const service = new DeploymentService({ source });

    const board = await service.board();

    assert.equal(board.ok, false);
    if (board.ok) return;
    assert.equal(board.error.kind, 'timeout');
  });

  it('сортирует успешные деплои по версии релиза', async () => {
    const service = new DeploymentService({ source: new FixtureDeploymentSource() });
    const latest = await service.latestVersions();

    assert.equal(latest.ok, true);
    if (!latest.ok) return;
    assert.equal(latest.value[0]?.release.version, '1.6.0');
  });
});

describe('CachedDeploymentSource', () => {
  it('не ходит в источник повторно за тем же запросом', async () => {
    const inner = new StubSource(fixtureDeployments);
    const cached = new CachedDeploymentSource(inner, 60_000);

    await cached.list(EMPTY_QUERY);
    await cached.list(EMPTY_QUERY);

    assert.equal(inner.listCalls, 1);
  });

  it('различает запросы с разными фильтрами', async () => {
    const inner = new StubSource(fixtureDeployments);
    const cached = new CachedDeploymentSource(inner, 60_000);

    await cached.list(EMPTY_QUERY);
    await cached.list({ ...EMPTY_QUERY, environment: 'dev' });

    assert.equal(inner.listCalls, 2);
  });

  it('сбрасывает кеш по требованию', async () => {
    const inner = new StubSource(fixtureDeployments);
    const cached = new CachedDeploymentSource(inner, 60_000);

    await cached.list(EMPTY_QUERY);
    cached.invalidate();
    await cached.list(EMPTY_QUERY);

    assert.equal(inner.listCalls, 2);
  });
});
