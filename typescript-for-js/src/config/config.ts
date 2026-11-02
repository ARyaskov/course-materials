import type { LogLevel } from '#services/ports.ts';

import { parseEnum, parseNumber, parseString } from './parse.ts';

export const SOURCE_KINDS = ['fixtures', 'http'] as const;
export type SourceKind = (typeof SOURCE_KINDS)[number];

const LOG_LEVELS = ['debug', 'info', 'warn', 'error'] as const satisfies readonly LogLevel[];

export interface AppConfig {
  readonly source: SourceKind;
  readonly apiBaseUrl: string;
  readonly timeoutMs: number;
  readonly retries: number;
  readonly cacheTtlMs: number;
  readonly port: number;
  readonly logLevel: LogLevel;
}

export type Env = Readonly<Record<string, string | undefined>>;

export const DEFAULT_CONFIG: AppConfig = {
  source: 'fixtures',
  apiBaseUrl: 'http://127.0.0.1:8080/api',
  timeoutMs: 5000,
  retries: 2,
  cacheTtlMs: 30_000,
  port: 8080,
  logLevel: 'info',
};

/**
 * Конфигурация собирается один раз при старте: дальше по коду ходит
 * готовый объект, а не process.env, разбросанный по модулям.
 */
export function loadConfig(env: Env): AppConfig {
  return {
    source: parseEnum(env['SHIPYARD_SOURCE'], SOURCE_KINDS, DEFAULT_CONFIG.source),
    apiBaseUrl: parseString(env['SHIPYARD_API_URL'], DEFAULT_CONFIG.apiBaseUrl),
    timeoutMs: parseNumber(env['SHIPYARD_TIMEOUT_MS'], DEFAULT_CONFIG.timeoutMs),
    retries: parseNumber(env['SHIPYARD_RETRIES'], DEFAULT_CONFIG.retries),
    cacheTtlMs: parseNumber(env['SHIPYARD_CACHE_TTL_MS'], DEFAULT_CONFIG.cacheTtlMs),
    port: parseNumber(env['PORT'], DEFAULT_CONFIG.port),
    logLevel: parseEnum(env['SHIPYARD_LOG_LEVEL'], LOG_LEVELS, DEFAULT_CONFIG.logLevel),
  };
}

export function describeConfig(config: AppConfig): string {
  const parts = [
    `источник: ${config.source}`,
    config.source === 'http' ? `api: ${config.apiBaseUrl}` : null,
    `таймаут: ${config.timeoutMs} мс`,
    `повторы: ${config.retries}`,
    `лог: ${config.logLevel}`,
  ];

  return parts.filter((part) => part !== null).join(', ');
}
