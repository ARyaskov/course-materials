import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { fixtureDeployments } from '#fixtures/deployments.ts';
import { toPublicDto, toSummaryDto, toSummaryDtos } from '#sdk/mappers.ts';
import { compareVersions, formatVersion, isPrerelease, parseVersion } from '#domain/version.ts';
import { isArrayOf, isNonEmptyString, isRecord, hasKey } from '#lib/guards.ts';
import { pick, omit, shallowEqual, objectKeys } from '#lib/objects.ts';

const [first] = fixtureDeployments;

describe('DTO публичного SDK', () => {
  it('сводный DTO плоский и содержит версию релиза', () => {
    assert.ok(first !== undefined);
    const dto = toSummaryDto(first);

    assert.equal(dto.id, first.id);
    assert.equal(dto.version, first.release.version);
    assert.equal(typeof dto.startedAt, 'string');
    assert.equal(dto.durationMs, 402_000);
  });

  it('публичный DTO не содержит внутренний комментарий', () => {
    assert.ok(first !== undefined);
    const dto = toPublicDto(first);

    assert.equal(Object.hasOwn(dto, 'comment'), false);
    assert.equal(dto.status, 'succeeded');
  });

  it('сохраняет длительность null для незавершённых', () => {
    const dtos = toSummaryDtos(fixtureDeployments);
    const queued = dtos.find((dto) => dto.status === 'queued');

    assert.equal(queued?.durationMs, null);
    assert.equal(dtos.length, fixtureDeployments.length);
  });
});

describe('версии', () => {
  it('разбирает и печатает версию', () => {
    const version = parseVersion('v1.5.1-rc.1');

    assert.ok(version !== null);
    assert.equal(version.minor, 5);
    assert.equal(isPrerelease(version), true);
    assert.equal(formatVersion(version), '1.5.1-rc.1');
  });

  it('возвращает null для мусора', () => {
    assert.equal(parseVersion('релиз от вторника'), null);
  });

  it('считает релиз старше своего prerelease', () => {
    const stable = parseVersion('1.5.1');
    const rc = parseVersion('1.5.1-rc.1');

    assert.ok(stable !== null && rc !== null);
    assert.equal(compareVersions(stable, rc), 1);
    assert.equal(compareVersions(rc, stable), -1);
    assert.equal(compareVersions(stable, stable), 0);
  });
});

describe('охранные функции и объекты', () => {
  it('различают структуры данных', () => {
    assert.equal(isRecord({}), true);
    assert.equal(isRecord([]), false);
    assert.equal(isRecord(null), false);
    assert.equal(isArrayOf(['a', 'b'], isNonEmptyString), true);
    assert.equal(isArrayOf(['a', ''], isNonEmptyString), false);
    assert.equal(hasKey({ id: 1 }, 'id'), true);
  });

  it('копируют объекты по ключам', () => {
    const source = { id: 'dep_001', status: 'succeeded', comment: 'ok' };

    assert.deepEqual(pick(source, ['id']), { id: 'dep_001' });
    assert.deepEqual(omit(source, ['comment']), { id: 'dep_001', status: 'succeeded' });
    assert.deepEqual(objectKeys(source), ['id', 'status', 'comment']);
    assert.equal(shallowEqual(source, { ...source }), true);
    assert.equal(shallowEqual(source, { ...source, comment: 'нет' }), false);
  });
});
