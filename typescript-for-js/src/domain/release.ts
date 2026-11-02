import type { ReleaseId } from './ids.ts';

/** Строка времени в формате ISO 8601 (UTC). */
export type IsoDateTime = string;

export interface Release {
  readonly id: ReleaseId;
  readonly version: string;
  readonly commitSha: string;
  readonly author: string;
}

export function shortSha(release: Release): string {
  return release.commitSha.slice(0, 7);
}
