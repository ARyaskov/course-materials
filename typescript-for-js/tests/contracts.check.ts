/**
 * Контракт между слоями, зафиксированный типами: DTO, доменная модель
 * и публичный SDK не должны разъезжаться незаметно.
 */
import type { DeploymentDto } from '#api/dto.ts';
import type { Deployment } from '#domain/deployment.ts';
import type { DeploymentStatus } from '#domain/deployment-status.ts';
import type { fromDeployment, toDeployment } from '#api/mappers.ts';
import type { DeploymentSummaryDto, PublicDeploymentDto } from '#sdk/dto.ts';
import type { DeploymentSource } from '#services/ports.ts';
import type { FixtureDeploymentSource } from '#api/fixture-source.ts';
import type { HttpDeploymentSource } from '#api/http-source.ts';
import type { CachedDeploymentSource } from '#api/cached-source.ts';

import type { Equal, Expect } from './types.check.ts';

/** Набор статусов на проводе совпадает с доменным. */
export type WireStatusesMatchDomain = Expect<Equal<DeploymentDto['status'], DeploymentStatus>>;

/** Отображения обратимы по типам: DTO -> домен -> DTO. */
export type MapperRoundTrip = Expect<
  Equal<ReturnType<typeof fromDeployment>, Parameters<typeof toDeployment>[0]>
>;

export type MapperReturnsDomain = Expect<Equal<ReturnType<typeof toDeployment>, Deployment>>;

/** Публичный DTO не должен раскрывать внутренний комментарий. */
export type PublicDtoHasNoComment = Expect<
  'comment' extends keyof PublicDeploymentDto ? false : true
>;

export type SummaryDtoIsFlat = Expect<Equal<DeploymentSummaryDto['version'], string>>;

/** Все реализации порта взаимозаменяемы. */
export type FixtureImplementsPort = Expect<
  FixtureDeploymentSource extends DeploymentSource ? true : false
>;
export type HttpImplementsPort = Expect<
  HttpDeploymentSource extends DeploymentSource ? true : false
>;
export type CacheImplementsPort = Expect<
  CachedDeploymentSource extends DeploymentSource ? true : false
>;
