export type JsonValue =
  | string
  | number
  | boolean
  | null
  | readonly JsonValue[]
  | { readonly [key: string]: JsonValue };

/** Единственное место в проекте, где вызывается JSON.parse. */
export function parseJson(raw: string): unknown {
  return JSON.parse(raw) as unknown;
}

/** Единственное место в проекте, где вызывается response.json(). */
export async function readJsonResponse(response: Response): Promise<unknown> {
  return await response.json();
}

export function stringifyJson(value: unknown, pretty = false): string {
  return pretty ? JSON.stringify(value, null, 2) : JSON.stringify(value);
}
