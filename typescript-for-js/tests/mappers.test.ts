import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { fromDeployment, toDeployment } from '#api/mappers.ts';
import { parseWith } from '#api/parser.ts';
import { deploymentListSchema, deploymentSchema } from '#api/schemas.ts';
import { fixtureDeployments } from '#fixtures/deployments.ts';

const VALID_FAILED = {
  id: 'dep_002',
  environment: 'production',
  status: 'failed',
  release: {
    id: 'rel_141',
    version: '1.4.1',
    commit_sha: '3f0aa19c77d21b04',
    author: 'anna.k',
  },
  requested_by: 'anna.k',
  comment: null,
  started_at: '2026-08-29T11:40:10.000Z',
  finished_at: '2026-08-29T11:44:55.000Z',
  duration_ms: 285_000,
  reason: 'health-check не прошёл',
  exit_code: 7,
};

describe('схема деплоя', () => {
  it('принимает корректные данные', () => {
    const parsed = parseWith(deploymentSchema, VALID_FAILED);
    assert.equal(parsed.ok, true);
  });

  it('отвергает неизвестный статус и сообщает поле', () => {
    const parsed = parseWith(deploymentSchema, { ...VALID_FAILED, status: 'canceled' });

    assert.equal(parsed.ok, false);
    if (parsed.ok) return;

    assert.equal(parsed.error.kind, 'invalid_shape');
    if (parsed.error.kind !== 'invalid_shape') return;
    assert.ok(parsed.error.issues.some((issue) => issue.includes('status')));
  });

  it('не пропускает деплой без обязательных полей статуса', () => {
    const { reason: _reason, ...withoutReason } = VALID_FAILED;
    assert.equal(parseWith(deploymentSchema, withoutReason).ok, false);
  });

  it('считает отсутствующий комментарий значением null', () => {
    const { comment: _comment, ...withoutComment } = VALID_FAILED;
    const parsed = parseWith(deploymentSchema, withoutComment);

    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.value.comment, null);
  });

  it('проверяет формат идентификатора', () => {
    assert.equal(parseWith(deploymentSchema, { ...VALID_FAILED, id: '17' }).ok, false);
  });
});

describe('преобразование DTO', () => {
  it('переносит поля в доменную модель', () => {
    const parsed = parseWith(deploymentSchema, VALID_FAILED);
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;

    const deployment = toDeployment(parsed.value);

    assert.equal(deployment.status, 'failed');
    if (deployment.status !== 'failed') return;

    assert.equal(deployment.exitCode, 7);
    assert.equal(deployment.release.commitSha, '3f0aa19c77d21b04');
    assert.equal(deployment.requestedBy, 'anna.k');
  });

  it('обратимо для всех фикстур', () => {
    for (const deployment of fixtureDeployments) {
      const dto = fromDeployment(deployment);
      const parsed = parseWith(deploymentSchema, dto);

      assert.equal(parsed.ok, true, `не разобрался ${deployment.id}`);
      if (!parsed.ok) continue;

      assert.deepEqual(toDeployment(parsed.value), deployment);
    }
  });

  it('разбирает ответ списка целиком', () => {
    const payload = {
      data: fixtureDeployments.map(fromDeployment),
      meta: { total: fixtureDeployments.length, limit: 20, offset: 0 },
    };

    const parsed = parseWith(deploymentListSchema, payload);
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;

    assert.equal(parsed.value.data.length, fixtureDeployments.length);
  });
});
