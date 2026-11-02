import type { Deployment } from '#domain/deployment.ts';
import { requireDeploymentId, toReleaseId } from '#domain/ids.ts';
import type { ReleaseId } from '#domain/ids.ts';
import type { Release } from '#domain/release.ts';

function releaseId(value: string): ReleaseId {
  const id = toReleaseId(value);
  if (id === null) throw new Error(`Некорректный идентификатор релиза: ${value}`);
  return id;
}

function release(id: string, version: string, commitSha: string, author: string): Release {
  return { id: releaseId(id), version, commitSha, author };
}

const releases = {
  r140: release('rel_140', '1.4.0', 'b71c9a4f0d3e5a71', 'anna.k'),
  r141: release('rel_141', '1.4.1', '3f0aa19c77d21b04', 'anna.k'),
  r150: release('rel_150', '1.5.0', 'ce41d0b8a2f39917', 'ilya.v'),
  r151: release('rel_151', '1.5.1-rc.1', '9a02fe7cb3d14e60', 'ilya.v'),
  r160: release('rel_160', '1.6.0', '52d7c81aef049b3d', 'marina.s'),
} as const satisfies Record<string, Release>;

/** Набор данных, на котором проект запускается без внешнего API. */
export const fixtureDeployments: readonly Deployment[] = [
  {
    id: requireDeploymentId('dep_001'),
    environment: 'production',
    release: releases.r140,
    requestedBy: 'anna.k',
    comment: 'плановый релиз',
    status: 'succeeded',
    startedAt: '2026-08-28T09:12:00.000Z',
    finishedAt: '2026-08-28T09:18:42.000Z',
    durationMs: 402_000,
  },
  {
    id: requireDeploymentId('dep_002'),
    environment: 'production',
    release: releases.r141,
    requestedBy: 'anna.k',
    comment: 'хотфикс биллинга',
    status: 'failed',
    startedAt: '2026-08-29T11:40:10.000Z',
    finishedAt: '2026-08-29T11:44:55.000Z',
    durationMs: 285_000,
    reason: 'health-check не прошёл на 3 из 6 подов',
    exitCode: 7,
  },
  {
    id: requireDeploymentId('dep_003'),
    environment: 'production',
    release: releases.r140,
    requestedBy: 'oncall',
    comment: 'откат после dep_002',
    status: 'rolled_back',
    startedAt: '2026-08-29T11:47:00.000Z',
    finishedAt: '2026-08-29T11:51:30.000Z',
    durationMs: 270_000,
    revertedTo: releases.r140.id,
  },
  {
    id: requireDeploymentId('dep_004'),
    environment: 'staging',
    release: releases.r150,
    requestedBy: 'ilya.v',
    comment: null,
    status: 'succeeded',
    startedAt: '2026-08-30T08:05:00.000Z',
    finishedAt: '2026-08-30T08:11:20.000Z',
    durationMs: 380_000,
  },
  {
    id: requireDeploymentId('dep_005'),
    environment: 'staging',
    release: releases.r151,
    requestedBy: 'ilya.v',
    comment: 'проверка миграции',
    status: 'failed',
    startedAt: '2026-08-31T14:02:00.000Z',
    finishedAt: '2026-08-31T14:03:12.000Z',
    durationMs: 72_000,
    reason: 'миграция 0042 упала на таблице releases',
    exitCode: 1,
  },
  {
    id: requireDeploymentId('dep_006'),
    environment: 'dev',
    release: releases.r151,
    requestedBy: 'ilya.v',
    comment: null,
    status: 'succeeded',
    startedAt: '2026-08-31T15:20:00.000Z',
    finishedAt: '2026-08-31T15:22:05.000Z',
    durationMs: 125_000,
  },
  {
    id: requireDeploymentId('dep_007'),
    environment: 'dev',
    release: releases.r160,
    requestedBy: 'marina.s',
    comment: 'ветка feature/board-filters',
    status: 'succeeded',
    startedAt: '2026-09-01T10:00:00.000Z',
    finishedAt: '2026-09-01T10:02:40.000Z',
    durationMs: 160_000,
  },
  {
    id: requireDeploymentId('dep_008'),
    environment: 'staging',
    release: releases.r160,
    requestedBy: 'marina.s',
    comment: null,
    status: 'running',
    startedAt: '2026-09-01T12:15:00.000Z',
  },
  {
    id: requireDeploymentId('dep_009'),
    environment: 'production',
    release: releases.r160,
    requestedBy: 'anna.k',
    comment: 'ждёт подтверждения релиз-менеджера',
    status: 'queued',
    queuedAt: '2026-09-01T12:30:00.000Z',
  },
  {
    id: requireDeploymentId('dep_010'),
    environment: 'dev',
    release: releases.r160,
    requestedBy: 'marina.s',
    comment: 'ночная сборка',
    status: 'succeeded',
    startedAt: '2026-09-02T02:00:00.000Z',
    finishedAt: '2026-09-02T02:03:30.000Z',
    durationMs: 210_000,
  },
];

export function findFixture(id: string): Deployment | undefined {
  return fixtureDeployments.find((deployment) => deployment.id === id);
}
