import type { ServerResponse } from 'node:http';

import type { JsonValue } from '#lib/json.ts';
import { stringifyJson } from '#lib/json.ts';

export function sendJson(response: ServerResponse, status: number, body: JsonValue): void {
  const payload = stringifyJson(body, true);

  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(payload),
    'cache-control': 'no-store',
  });

  response.end(payload);
}

export function sendText(
  response: ServerResponse,
  status: number,
  text: string,
  contentType = 'text/plain; charset=utf-8',
): void {
  response.writeHead(status, {
    'content-type': contentType,
    'content-length': Buffer.byteLength(text),
  });

  response.end(text);
}

export function sendError(response: ServerResponse, status: number, message: string): void {
  sendJson(response, status, { error: { status, message } });
}
