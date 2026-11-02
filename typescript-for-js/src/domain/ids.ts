declare const brand: unique symbol;

/** Брендированный тип: значение остаётся строкой в рантайме, но не смешивается с другими. */
export type Brand<T, B extends string> = T & { readonly [brand]: B };

export type DeploymentId = Brand<string, 'DeploymentId'>;
export type ReleaseId = Brand<string, 'ReleaseId'>;

const DEPLOYMENT_ID_RE = /^dep_[0-9a-z]{3,}$/;
const RELEASE_ID_RE = /^rel_[0-9a-z]{2,}$/;

export function isDeploymentId(value: string): value is DeploymentId {
  return DEPLOYMENT_ID_RE.test(value);
}

export function isReleaseId(value: string): value is ReleaseId {
  return RELEASE_ID_RE.test(value);
}

export function toDeploymentId(value: string): DeploymentId | null {
  return isDeploymentId(value) ? value : null;
}

export function toReleaseId(value: string): ReleaseId | null {
  return isReleaseId(value) ? value : null;
}

export function requireDeploymentId(value: string): DeploymentId {
  const id = toDeploymentId(value);
  if (id === null) throw new Error(`Некорректный идентификатор деплоя: ${value}`);
  return id;
}
