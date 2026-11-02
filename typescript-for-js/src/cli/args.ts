import { parseArgs } from 'node:util';

import { DEPLOYMENT_STATUSES, isDeploymentStatus } from '#domain/deployment-status.ts';
import type { DeploymentStatus } from '#domain/deployment-status.ts';
import { ENVIRONMENTS, isEnvironment } from '#domain/environment.ts';
import type { Environment } from '#domain/environment.ts';
import { DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE } from '#domain/constants.ts';
import { err, ok } from '#lib/result.ts';
import type { Result } from '#lib/result.ts';
import { toPositiveInt } from '#lib/number.ts';

export const COMMANDS = ['status', 'show', 'serve', 'help'] as const;
export type Command = (typeof COMMANDS)[number];

export interface CliOptions {
  readonly command: Command;
  readonly positional: readonly string[];
  readonly environment: Environment | null;
  readonly status: DeploymentStatus | null;
  readonly author: string | null;
  readonly limit: number;
  readonly json: boolean;
  readonly port: number | null;
  readonly help: boolean;
}

/** Пара «флаг — значение»: именованный кортеж читается лучше, чем [string, string]. */
export type FlagPair = readonly [flag: string, value: string];

const OPTION_SPEC = {
  env: { type: 'string' },
  status: { type: 'string' },
  author: { type: 'string' },
  limit: { type: 'string' },
  port: { type: 'string' },
  json: { type: 'boolean', default: false },
  help: { type: 'boolean', short: 'h', default: false },
} as const;

function isCommand(value: string): value is Command {
  return (COMMANDS as readonly string[]).includes(value);
}

export function parseCliArgs(argv: readonly string[]): Result<CliOptions, string> {
  let parsed;
  try {
    parsed = parseArgs({
      args: [...argv],
      options: OPTION_SPEC,
      allowPositionals: true,
      strict: true,
    });
  } catch (caught) {
    return err(caught instanceof Error ? caught.message : String(caught));
  }

  const [rawCommand = 'status', ...rest] = parsed.positionals;
  if (!isCommand(rawCommand)) {
    return err(`Неизвестная команда «${rawCommand}». Доступны: ${COMMANDS.join(', ')}`);
  }

  const { values } = parsed;

  const environment = values.env ?? null;
  if (environment !== null && !isEnvironment(environment)) {
    return err(`Неизвестное окружение «${environment}». Доступны: ${ENVIRONMENTS.join(', ')}`);
  }

  const status = values.status ?? null;
  if (status !== null && !isDeploymentStatus(status)) {
    return err(`Неизвестный статус «${status}». Доступны: ${DEPLOYMENT_STATUSES.join(', ')}`);
  }

  const limit = values.limit === undefined ? DEFAULT_PAGE_SIZE : toPositiveInt(values.limit);
  if (limit === null || limit > MAX_PAGE_SIZE) {
    return err(`Некорректный --limit: ожидалось целое число от 1 до ${MAX_PAGE_SIZE}`);
  }

  const port = values.port === undefined ? null : toPositiveInt(values.port);
  if (values.port !== undefined && port === null) {
    return err('Некорректный --port: ожидалось положительное целое число');
  }

  return ok({
    command: rawCommand,
    positional: rest,
    environment,
    status,
    author: values.author ?? null,
    limit,
    json: values.json,
    port,
    help: values.help,
  });
}

/** Разбор строки вида `--env=production` для подсказок в help. */
export function splitFlag(input: string): FlagPair | null {
  const separator = input.indexOf('=');
  if (!input.startsWith('--') || separator === -1) return null;

  return [input.slice(2, separator), input.slice(separator + 1)] as const;
}
