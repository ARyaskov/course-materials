import { fileURLToPath } from 'node:url';

import type { AppConfig } from '#config/config.ts';
import { startServer } from '#server/http.ts';
import type { DeploymentService } from '#services/deployment-service.ts';
import type { Logger } from '#services/ports.ts';

import type { CliOptions } from '../args.ts';
import type { CommandIo } from './status.ts';

const STATIC_ROOT = fileURLToPath(new URL('../../../public', import.meta.url));

/** Ждём сигнала завершения: сервер живёт, пока не нажмут Ctrl+C. */
function waitForShutdown(): Promise<NodeJS.Signals> {
  return new Promise((resolve) => {
    const onSignal = (signal: NodeJS.Signals): void => {
      process.off('SIGINT', onSignal);
      process.off('SIGTERM', onSignal);
      resolve(signal);
    };

    process.once('SIGINT', onSignal);
    process.once('SIGTERM', onSignal);
  });
}

export async function runServe(
  service: DeploymentService,
  options: CliOptions,
  config: AppConfig,
  io: CommandIo,
  logger: Logger,
): Promise<number> {
  const port = options.port ?? config.port;

  try {
    const server = await startServer({ service, port, staticRoot: STATIC_ROOT, logger });

    io.out(`Доска деплоев: ${server.url}\n`);
    io.out(`JSON API: ${server.url}/api/deployments\n`);
    io.out('Остановить: Ctrl+C\n');

    const signal = await waitForShutdown();
    logger.log('info', `Получен сигнал ${signal}, останавливаем сервер`);
    await server.close();

    return 0;
  } catch (caught) {
    io.error(`Не удалось запустить сервер на порту ${port}: ${String(caught)}\n`);
    return 1;
  }
}
