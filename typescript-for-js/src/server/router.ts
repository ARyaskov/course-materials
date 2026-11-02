import type { IncomingMessage, ServerResponse } from 'node:http';

import { sendError } from './respond.ts';

export interface RequestContext {
  readonly request: IncomingMessage;
  readonly response: ServerResponse;
  readonly url: URL;
  readonly params: Readonly<Record<string, string>>;
}

export type RouteHandler = (context: RequestContext) => Promise<void> | void;

export interface Route {
  readonly method: 'GET' | 'POST';
  /** Шаблон вида /api/deployments/:id — параметры попадают в context.params. */
  readonly pattern: string;
  readonly handler: RouteHandler;
}

function matchPattern(pattern: string, pathname: string): Readonly<Record<string, string>> | null {
  const patternParts = pattern.split('/').filter((part) => part.length > 0);
  const pathParts = pathname.split('/').filter((part) => part.length > 0);

  if (patternParts.length !== pathParts.length) return null;

  const params: Record<string, string> = {};

  for (const [index, patternPart] of patternParts.entries()) {
    const pathPart = pathParts[index];
    if (pathPart === undefined) return null;

    if (patternPart.startsWith(':')) {
      params[patternPart.slice(1)] = decodeURIComponent(pathPart);
      continue;
    }

    if (patternPart !== pathPart) return null;
  }

  return params;
}

export type Middleware = (context: RequestContext) => Promise<boolean> | boolean;

export interface RouterOptions {
  readonly routes: readonly Route[];
  /** Вызывается, если ни один маршрут не подошёл; true означает «ответ отправлен». */
  readonly fallback?: Middleware;
  readonly onError?: (error: unknown, context: RequestContext) => void;
}

export function createRouter(options: RouterOptions) {
  return async function handle(request: IncomingMessage, response: ServerResponse): Promise<void> {
    let url: URL;
    try {
      url = new URL(request.url ?? '/', `http://${request.headers.host ?? 'localhost'}`);
      // Проверяем кодирование до разбора параметров и обращения к статике.
      decodeURI(url.pathname);
    } catch {
      sendError(response, 400, 'Некорректный URL');
      return;
    }

    const method = request.method ?? 'GET';
    let context: RequestContext = { request, response, url, params: {} };

    try {
      for (const route of options.routes) {
        if (route.method !== method) continue;

        const params = matchPattern(route.pattern, url.pathname);
        if (params === null) continue;

        context = { request, response, url, params };
        await route.handler(context);
        return;
      }

      const handled = (await options.fallback?.(context)) ?? false;

      if (!handled) sendError(response, 404, `Не найдено: ${method} ${url.pathname}`);
    } catch (caught) {
      options.onError?.(caught, context);
      if (!response.headersSent) sendError(response, 500, 'Внутренняя ошибка сервера');
      else response.destroy();
    }
  };
}
