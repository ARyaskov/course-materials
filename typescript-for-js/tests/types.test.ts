import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { HttpClient } from '#api/client.ts';
import { fromDeployment, toDeployment } from '#api/mappers.ts';
import { buildUrl } from '#api/url.ts';
import { DEPLOYMENT_STATUSES, STATUS_TITLES } from '#domain/deployment-status.ts';
import type { DeploymentStatus } from '#domain/deployment-status.ts';
import { ENVIRONMENTS, ENVIRONMENT_TITLES } from '#domain/environment.ts';
import type { Environment } from '#domain/environment.ts';
import { fixtureDeployments } from '#fixtures/deployments.ts';
import { summarize } from '#reports/summary.ts';

import type { Equal, Expect } from './types.check.ts';
import { stubFetch } from './doubles.ts';

/** ReturnType и Parameters связывают тесты с реальными сигнатурами. */
type ClientResult = Awaited<ReturnType<HttpClient['getJson']>>;
type MapperInput = Parameters<typeof toDeployment>[0];

export type ClientReturnsResult = Expect<
  Equal<ClientResult['ok'], boolean>
>;
export type MapperTakesDto = Expect<Equal<MapperInput, ReturnType<typeof fromDeployment>>>;

describe('utility types в работе', () => {
  it('ReturnType и Awaited описывают ответ клиента', async () => {
    const stub = stubFetch([{ body: { data: [], meta: null } }]);
    const client = new HttpClient({ baseUrl: 'https://api.example.com', fetchImpl: stub.fetch });

    const result: ClientResult = await client.getJson('/deployments');

    assert.equal(result.ok, true);
  });

  it('Parameters фиксирует форму входа маппера', () => {
    const [first] = fixtureDeployments;
    assert.ok(first !== undefined);

    const dto: MapperInput = fromDeployment(first);
    assert.deepEqual(toDeployment(dto), first);
  });
});

describe('satisfies', () => {
  it('таблицы заголовков покрывают все варианты объединения', () => {
    const statusKeys = Object.keys(STATUS_TITLES) as DeploymentStatus[];
    const environmentKeys = Object.keys(ENVIRONMENT_TITLES) as Environment[];

    assert.deepEqual(statusKeys.toSorted(), [...DEPLOYMENT_STATUSES].toSorted());
    assert.deepEqual(environmentKeys.toSorted(), [...ENVIRONMENTS].toSorted());
  });

  it('сохраняет литеральные типы значений', () => {
    // Благодаря satisfies это не просто string, а конкретный литерал.
    const title: 'ошибка' = STATUS_TITLES.failed;
    assert.equal(title, 'ошибка');
  });

  it('сводка содержит запись по каждому окружению', () => {
    const summary = summarize(fixtureDeployments);
    const seen = summary.environments.map((item) => item.environment);

    assert.deepEqual(seen, [...ENVIRONMENTS]);
  });
});

describe('buildUrl', () => {
  it('склеивает базовый адрес и путь без двойных слэшей', () => {
    assert.equal(buildUrl('https://api.example.com/v1/', '/deployments'), 'https://api.example.com/v1/deployments');
    assert.equal(
      buildUrl('https://api.example.com', 'deployments', { limit: 5, author: null }),
      'https://api.example.com/deployments?limit=5',
    );
  });
});
