import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { HttpClient } from '#api/client.ts';
import { fromDeployment } from '#api/mappers.ts';
import { HttpDeploymentSource } from '#api/http-source.ts';
import { EMPTY_QUERY } from '#domain/query.ts';
import { requireDeploymentId } from '#domain/ids.ts';
import { fixtureDeployments } from '#fixtures/deployments.ts';

import { stubFetch } from '../doubles.ts';

const LIST_PAYLOAD = {
  data: fixtureDeployments.map(fromDeployment),
  meta: { total: fixtureDeployments.length, limit: 20, offset: 0 },
};

describe('HttpClient', () => {
  it('собирает URL с параметрами и пропускает пустые', async () => {
    const stub = stubFetch([{ body: LIST_PAYLOAD }]);
    const client = new HttpClient({ baseUrl: 'https://api.example.com/v1', fetchImpl: stub.fetch });

    await client.getJson('/deployments', { environment: 'production', status: null, limit: 5 });

    assert.equal(
      stub.calls[0]?.url,
      'https://api.example.com/v1/deployments?environment=production&limit=5',
    );
  });

  it('возвращает ошибку http без выброса исключения', async () => {
    const stub = stubFetch([{ status: 404, body: {} }]);
    const client = new HttpClient({
      baseUrl: 'https://api.example.com',
      fetchImpl: stub.fetch,
      retries: 0,
    });

    const result = await client.getJson('/deployments');

    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.error.kind, 'http');
  });

  it('повторяет запрос при ошибке сети', async () => {
    const stub = stubFetch([{ fail: new TypeError('fetch failed') }, { body: LIST_PAYLOAD }]);
    const client = new HttpClient({
      baseUrl: 'https://api.example.com',
      fetchImpl: stub.fetch,
      retries: 1,
    });

    const result = await client.getJson('/deployments');

    assert.equal(result.ok, true);
    assert.equal(stub.calls.length, 2);
  });

  it('не повторяет запрос при ошибке клиента', async () => {
    const stub = stubFetch([{ status: 400, body: {} }]);
    const client = new HttpClient({
      baseUrl: 'https://api.example.com',
      fetchImpl: stub.fetch,
      retries: 3,
    });

    await client.getJson('/deployments');

    assert.equal(stub.calls.length, 1);
  });

  it('сообщает о некорректном JSON', async () => {
    const stub = stubFetch([{ rawBody: 'не json' }]);
    const client = new HttpClient({
      baseUrl: 'https://api.example.com',
      fetchImpl: stub.fetch,
      retries: 0,
    });

    const result = await client.getJson('/deployments');

    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.error.kind, 'invalid_json');
  });
});

describe('HttpDeploymentSource', () => {
  it('превращает ответ в доменные объекты', async () => {
    const stub = stubFetch([{ body: LIST_PAYLOAD }]);
    const source = new HttpDeploymentSource(
      new HttpClient({ baseUrl: 'https://api.example.com', fetchImpl: stub.fetch }),
    );

    const page = await source.list(EMPTY_QUERY);

    assert.equal(page.ok, true);
    if (!page.ok) return;

    assert.equal(page.value.items.length, fixtureDeployments.length);
    assert.equal(page.value.items[0]?.release.commitSha, 'b71c9a4f0d3e5a71');
  });

  it('отдаёт null вместо ошибки, если деплой не найден', async () => {
    const stub = stubFetch([{ status: 404, body: {} }]);
    const source = new HttpDeploymentSource(
      new HttpClient({ baseUrl: 'https://api.example.com', fetchImpl: stub.fetch, retries: 0 }),
    );

    const found = await source.byId(requireDeploymentId('dep_999'));

    assert.equal(found.ok, true);
    if (!found.ok) return;
    assert.equal(found.value, null);
  });

  it('не доверяет ответу, который не проходит схему', async () => {
    const stub = stubFetch([{ body: { data: [{ id: 'oops' }] } }]);
    const source = new HttpDeploymentSource(
      new HttpClient({ baseUrl: 'https://api.example.com', fetchImpl: stub.fetch }),
    );

    const page = await source.list(EMPTY_QUERY);

    assert.equal(page.ok, false);
    if (page.ok) return;
    assert.equal(page.error.kind, 'invalid_shape');
  });
});
