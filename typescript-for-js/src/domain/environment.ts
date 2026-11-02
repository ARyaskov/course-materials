export const ENVIRONMENTS = ['dev', 'staging', 'production'] as const;

export type Environment = (typeof ENVIRONMENTS)[number];

export const ENVIRONMENT_TITLES = {
  dev: 'Разработка',
  staging: 'Пред-прод',
  production: 'Продакшен',
} as const satisfies Record<Environment, string>;

export function environmentTitle(environment: Environment): string {
  return ENVIRONMENT_TITLES[environment];
}

export function isEnvironment(value: unknown): value is Environment {
  return typeof value === 'string' && (ENVIRONMENTS as readonly string[]).includes(value);
}
