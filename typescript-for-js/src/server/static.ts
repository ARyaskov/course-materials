import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize, resolve, sep } from 'node:path';

import type { Middleware } from './router.ts';
import { sendError } from './respond.ts';

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
} as const;

type KnownExtension = keyof typeof MIME_TYPES;

function contentTypeOf(filePath: string): string {
  const extension = extname(filePath);
  if (extension in MIME_TYPES) return MIME_TYPES[extension as KnownExtension];
  return 'application/octet-stream';
}

/** Путь склеивается только внутри корня: обход каталогов невозможен. */
function safeJoin(root: string, pathname: string): string | null {
  const relative = normalize(pathname).replace(/^([\\/])+/, '');
  const target = resolve(join(root, relative));

  return target === root || target.startsWith(root + sep) ? target : null;
}

export function createStaticMiddleware(root: string): Middleware {
  const rootDir = resolve(root);

  return async function serveStatic({ url, response }): Promise<boolean> {
    let pathname: string;
    try {
      pathname = decodeURIComponent(url.pathname);
    } catch {
      sendError(response, 400, 'Некорректный URL');
      return true;
    }
    const filePath = safeJoin(rootDir, pathname === '/' ? '/index.html' : pathname);
    if (filePath === null) return false;

    try {
      const stats = await stat(filePath);
      if (!stats.isFile()) return false;

      const content = await readFile(filePath);

      response.writeHead(200, {
        'content-type': contentTypeOf(filePath),
        'content-length': content.byteLength,
      });
      response.end(content);

      return true;
    } catch {
      return false;
    }
  };
}
