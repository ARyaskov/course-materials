import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { after, before, describe, it } from 'node:test';

import { FixtureDeploymentSource } from '#api/fixture-source.ts';
import { parseWith } from '#api/parser.ts';
import { deploymentListSchema } from '#api/schemas.ts';
import { ShipyardClient } from '#sdk/index.ts';
import { collectDeployments } from '#sdk/paginate.ts';
import { startServer } from '#server/http.ts';
import type { RunningServer } from '#server/http.ts';
import { DeploymentService } from '#services/deployment-service.ts';

const STATIC_ROOT = fileURLToPath(new URL('../public', import.meta.url));

describe('HTTP-сервер', () => {
  let server: RunningServer;
  let client: ShipyardClient;

  before(async () => {
    const service = new DeploymentService({ source: new FixtureDeploymentSource() });

    // Порт 0 — операционная система сама выберет свободный.
    server = await startServer({ service, port: 0, staticRoot: STATIC_ROOT });
    client = new ShipyardClient({ baseUrl: `${server.url}/api` });
  });

  after(async () => {
    await server.close();
  });

  it('отвечает на health-check', async () => {
    const response = await fetch(`${server.url}/api/health`);
    assert.equal(response.status, 200);

    const body: unknown = await response.json();
    assert.ok(typeof body === 'object' && body !== null && 'status' in body);
  });

  it('отдаёт список в формате, который принимает схема', async () => {
    const response = await fetch(`${server.url}/api/deployments?limit=3`);
    const payload: unknown = await response.json();

    const parsed = parseWith(deploymentListSchema, payload);
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;

    assert.equal(parsed.value.data.length, 3);
  });

  it('фильтрует по окружению', async () => {
    const page = await client.deployments({ environment: 'dev' });

    assert.equal(page.ok, true);
    if (!page.ok) return;

    assert.equal(
      page.value.items.every((item) => item.environment === 'dev'),
      true,
    );
  });

  it('возвращает 404 для несуществующего деплоя', async () => {
    const found = await client.deployment('dep_999');

    assert.equal(found.ok, true);
    if (!found.ok) return;
    assert.equal(found.value, null);
  });

  it('отдаёт сводку, проходящую схему SDK', async () => {
    const summary = await client.summary();

    assert.equal(summary.ok, true);
    if (!summary.ok) return;

    assert.equal(summary.value.total, 10);
    assert.equal(summary.value.environments.length, 3);
  });

  it('обходит все страницы через асинхронный итератор', async () => {
    const all = await collectDeployments(client, { limit: 4 });
    assert.equal(all.length, 10);
  });

  it('отдаёт статику доски', async () => {
    const response = await fetch(`${server.url}/`);

    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type') ?? '', /text\/html/);
  });

  it('не выпускает за пределы каталога public', async () => {
    const response = await fetch(`${server.url}/../package.json`);
    assert.equal(response.status, 404);
  });

  for (const path of [
    '/api/deployments/%',
    '/api/deployments/%GG',
    '/api/deployments/%E0%A4%A',
    '/%',
    '/%FF',
  ]) {
    it(`возвращает 400 для ${path} и продолжает работать`, async () => {
      const response = await fetch(`${server.url}${path}`);
      assert.equal(response.status, 400);
      assert.deepEqual(await response.json(), {
        error: { status: 400, message: 'Некорректный URL' },
      });
      assert.equal((await fetch(`${server.url}/api/health`)).status, 200);
    });
  }

  it('принимает корректно закодированный идентификатор', async () => {
    const response = await fetch(`${server.url}/api/deployments/dep_%30%30%31`);
    assert.equal(response.status, 200);
    const found = await client.deployment('dep_001');
    assert.equal(found.ok, true);
  });

  it('не выпускает за пределы public через закодированный путь', async () => {
    const response = await fetch(`${server.url}/%2e%2e%2fpackage.json`);
    assert.equal(response.status, 404);
  });

  for (const failingLogger of [false, true]) {
    it(`возвращает 500 при ошибке обработчика (сбой логгера: ${String(failingLogger)})`, async () => {
      const service = new DeploymentService({
        source: {
          list: () => Promise.reject(new Error('internal connection details')),
          byId: () => Promise.reject(new Error('internal connection details')),
        },
      });
      const isolated = await startServer({
        service,
        port: 0,
        staticRoot: STATIC_ROOT,
        logger: {
          log() {
            if (failingLogger) throw new Error('logger failed');
          },
        },
      });

      try {
        const response = await fetch(`${isolated.url}/api/deployments`);
        assert.equal(response.status, 500);
        assert.deepEqual(await response.json(), {
          error: { status: 500, message: 'Внутренняя ошибка сервера' },
        });
        assert.equal((await fetch(`${isolated.url}/api/health`)).status, 200);
      } finally {
        await isolated.close();
      }
    });
  }
});
