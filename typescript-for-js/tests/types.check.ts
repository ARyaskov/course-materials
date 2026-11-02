/**
 * Проверки уровня типов. Этот файл ничего не выполняет: он «падает»
 * во время `tsc --noEmit`, если типы перестали соответствовать ожиданиям.
 */
import type { Deployment, FinishedDeployment } from '#domain/deployment.ts';
import type { DeploymentId } from '#domain/ids.ts';
import type { Environment } from '#domain/environment.ts';
import type { DeploymentStatus } from '#domain/deployment-status.ts';
import type {
  DistributiveOmit,
  ElementOf,
  Expand,
  KeysOfType,
  Mutable,
  UnwrapResult,
} from '#lib/types.ts';
import type { Result } from '#lib/result.ts';

export type Equal<X, Y> =
  (<T>() => T extends X ? 1 : 2) extends <T>() => T extends Y ? 1 : 2 ? true : false;

export type Expect<T extends true> = T;
export type ExpectFalse<T extends false> = T;

/** Объединение статусов должно совпадать со списком констант. */
export type StatusesMatch = Expect<
  Equal<DeploymentStatus, 'queued' | 'running' | 'succeeded' | 'failed' | 'rolled_back'>
>;

export type EnvironmentsMatch = Expect<Equal<Environment, 'dev' | 'staging' | 'production'>>;

/** Завершённые деплои — это ровно три варианта объединения. */
export type FinishedStatuses = Expect<
  Equal<FinishedDeployment['status'], 'succeeded' | 'failed' | 'rolled_back'>
>;

/** Брендированный идентификатор нельзя подменить обычной строкой. */
export type IdIsNotString = ExpectFalse<Equal<DeploymentId, string>>;
export type IdIsAssignableToString = Expect<DeploymentId extends string ? true : false>;

/** Поля, которых нет у варианта, недоступны без сужения. */
export type ReasonOnlyOnFailed = Expect<
  Equal<Extract<Deployment, { status: 'failed' }>['reason'], string>
>;

export type UnwrapsOkValue = Expect<Equal<UnwrapResult<Result<number, Error>>, number>>;

export type OmitKeepsUnion = Expect<
  Equal<DistributiveOmit<Deployment, 'comment'>['status'], DeploymentStatus>
>;

export type ElementOfArray = Expect<Equal<ElementOf<readonly string[]>, string>>;

export type MutableDropsReadonly = Expect<
  Equal<Mutable<{ readonly a: number }>, { a: number }>
>;

export type ExpandKeepsShape = Expect<Equal<Expand<{ a: 1 }>, { a: 1 }>>;

export type StringKeysOfRelease = Expect<
  Equal<KeysOfType<{ a: string; b: number; c: string }, string>, 'a' | 'c'>
>;
