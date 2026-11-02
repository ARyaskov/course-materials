import type { Environment } from './environment.ts';

/** Сколько последних деплоев показываем по умолчанию. */
export const DEFAULT_PAGE_SIZE = 20;
export const MAX_PAGE_SIZE = 100;

/** Порог, после которого деплой считается подозрительно долгим. */
export const SLOW_DEPLOY_MS = 15 * 60 * 1000;

/** Окружения, куда нельзя катить без подтверждения. */
export const PROTECTED_ENVIRONMENTS = ['production'] as const satisfies readonly Environment[];

export function isProtected(environment: Environment): boolean {
  return (PROTECTED_ENVIRONMENTS as readonly Environment[]).includes(environment);
}
