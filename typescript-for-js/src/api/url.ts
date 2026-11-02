export type QueryValue = string | number | boolean | null | undefined;
export type QueryParams = Readonly<Record<string, QueryValue>>;

/** null и undefined в параметрах означают «не передавать», а не «передать пустым». */
export function buildQuery(params: QueryParams): string {
  const search = new URLSearchParams();

  for (const [key, value] of Object.entries(params)) {
    if (value === null || value === undefined) continue;
    search.set(key, String(value));
  }

  const query = search.toString();
  return query.length === 0 ? '' : `?${query}`;
}

export function joinUrl(baseUrl: string, path: string): string {
  const base = baseUrl.endsWith('/') ? baseUrl.slice(0, -1) : baseUrl;
  const tail = path.startsWith('/') ? path : `/${path}`;
  return `${base}${tail}`;
}

export function buildUrl(baseUrl: string, path: string, params: QueryParams = {}): string {
  return `${joinUrl(baseUrl, path)}${buildQuery(params)}`;
}
