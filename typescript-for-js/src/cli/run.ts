import { CachedDeploymentSource } from '#api/cached-source.ts';
import { HttpClient } from '#api/client.ts';
import { FixtureDeploymentSource } from '#api/fixture-source.ts';
import { HttpDeploymentSource } from '#api/http-source.ts';
import { loadConfig } from '#config/config.ts';
import type { AppConfig, Env } from '#config/config.ts';
import { assertNever } from '#lib/assert-never.ts';
import { DeploymentService } from '#services/deployment-service.ts';
import type { DeploymentSource, Logger } from '#services/ports.ts';

import { parseCliArgs } from './args.ts';
import { HELP_TEXT } from './help.ts';
import { createConsoleLogger } from './logger.ts';
import { runServe } from './commands/serve.ts';
import { runShow, runStatus } from './commands/status.ts';
import type { CommandIo } from './commands/status.ts';

export interface RunOptions {
  readonly argv: readonly string[];
  readonly env: Env;
  readonly io: CommandIo;
}

/** Композиционный корень: единственное место, где выбирается реализация порта. */
export function createSource(config: AppConfig): DeploymentSource {
  const base: DeploymentSource =
    config.source === 'fixtures'
      ? new FixtureDeploymentSource()
      : new HttpDeploymentSource(
          new HttpClient({
            baseUrl: config.apiBaseUrl,
            timeoutMs: config.timeoutMs,
            retries: config.retries,
          }),
        );

  return new CachedDeploymentSource(base, config.cacheTtlMs);
}

export async function run(options: RunOptions): Promise<number> {
  const parsed = parseCliArgs(options.argv);

  if (!parsed.ok) {
    options.io.error(`${parsed.error}\n\n`);
    options.io.error(HELP_TEXT);
    return 2;
  }

  const cli = parsed.value;

  if (cli.help) {
    options.io.out(HELP_TEXT);
    return 0;
  }

  if (cli.command === 'help') {
    options.io.out(HELP_TEXT);
    return 0;
  }

  const config = loadConfig(options.env);
  const logger: Logger = createConsoleLogger(config.logLevel);
  const service = new DeploymentService({ source: createSource(config), logger });

  switch (cli.command) {
    case 'status':
      return runStatus(service, cli, options.io);
    case 'show':
      return runShow(service, cli, options.io);
    case 'serve':
      return runServe(service, cli, config, options.io, logger);
    default:
      return assertNever(cli.command, 'run');
  }
}
