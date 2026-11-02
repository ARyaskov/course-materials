/**
 * Единственная публичная точка входа SDK. Всё, чего здесь нет,
 * считается внутренней деталью и может измениться без предупреждения.
 */
export { ShipyardClient } from './client.ts';
export type { ShipyardClientOptions } from './client.ts';

export { ShipyardError, toShipyardError } from './errors.ts';

export { collectDeployments, paginateDeployments } from './paginate.ts';

export { toPublicDto, toSummaryDto, toSummaryDtos } from './mappers.ts';
export type {
  DeploymentSummaryDto,
  ListDeploymentsRequest,
  ListDeploymentsResponse,
  PageInfoDto,
  PublicDeploymentDto,
  SdkErrorDto,
} from './dto.ts';

export type { SummaryResponse } from './schemas.ts';

export type { ApiError } from '#api/errors.ts';
export { describeApiError } from '#api/errors.ts';
export type { ApiResult, Page, PageMeta } from '#api/response.ts';

export type { Deployment, DeploymentStatus, Environment, Release } from '#domain/index.ts';
export { statusTitle, environmentTitle, shortSha } from '#domain/index.ts';
