import { createServer } from 'node:http';
import type { Server } from 'node:http';

import type { DeploymentService } from '#services/deployment-service.ts';
import type { Logger } from '#services/ports.ts';

import { getDeployment, getSummary, healthCheck, listDeployments } from './handlers/deployments.ts';
import { createRouter } from './router.ts';
import type { Route } from './router.ts';
import { sendError } from './respond.ts';
import { createStaticMiddleware } from './static.ts';

export interface ServerOptions {
  readonly service: DeploymentService;
  readonly port: number;
  readonly staticRoot: string;
  readonly logger?: Logger;
}

export interface RunningServer {
  readonly port: number;
  readonly url: string;
  close(): Promise<void>;
}

export function createRoutes(service: DeploymentService): readonly Route[] {
  return [
    { method: 'GET', pattern: '/api/health', handler: healthCheck() },
    { method: 'GET', pattern: '/api/deployments', handler: listDeployments(service) },
    { method: 'GET', pattern: '/api/deployments/:id', handler: getDeployment(service) },
    { method: 'GET', pattern: '/api/summary', handler: getSummary(service) },
  ];
}

/** Поднимает HTTP-сервер и возвращает управление после успешного listen. */
export function startServer(options: ServerOptions): Promise<RunningServer> {
  const handle = createRouter({
    routes: createRoutes(options.service),
    fallback: createStaticMiddleware(options.staticRoot),
    onError: (error) => options.logger?.log('error', 'Ошибка обработчика', String(error)),
  });

  const server: Server = createServer((request, response) => {
    void handle(request, response).catch(() => {
      if (response.destroyed) return;
      if (response.headersSent) {
        response.destroy();
        return;
      }
      sendError(response, 500, 'Внутренняя ошибка сервера');
    });
  });

  return new Promise((resolve, reject) => {
    server.once('error', reject);

    server.listen(options.port, '127.0.0.1', () => {
      const address = server.address();
      const port = typeof address === 'object' && address !== null ? address.port : options.port;

      resolve({
        port,
        url: `http://127.0.0.1:${port}`,
        close: () =>
          new Promise<void>((done, fail) => {
            server.close((error) => (error === undefined ? done() : fail(error)));
          }),
      });
    });
  });
}
