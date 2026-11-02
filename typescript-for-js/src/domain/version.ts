/** Разобранная семантическая версия релиза. */
export interface SemVer {
  readonly major: number;
  readonly minor: number;
  readonly patch: number;
  readonly prerelease: string | null;
}

const VERSION_RE = /^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9a-z.-]+))?$/i;

/** Возвращает null, если строка не является версией: вызывающий обязан это обработать. */
export function parseVersion(input: string): SemVer | null {
  const match = VERSION_RE.exec(input.trim());
  if (match === null) return null;

  const [, major, minor, patch, prerelease] = match;
  if (major === undefined || minor === undefined || patch === undefined) return null;

  return {
    major: Number(major),
    minor: Number(minor),
    patch: Number(patch),
    prerelease: prerelease ?? null,
  };
}

export function formatVersion(version: SemVer): string {
  const core = `${version.major}.${version.minor}.${version.patch}`;
  return version.prerelease === null ? core : `${core}-${version.prerelease}`;
}

export function isPrerelease(version: SemVer): boolean {
  return version.prerelease !== null;
}

export function compareVersions(left: SemVer, right: SemVer): -1 | 0 | 1 {
  const byCore =
    left.major - right.major || left.minor - right.minor || left.patch - right.patch;

  if (byCore !== 0) return byCore < 0 ? -1 : 1;
  if (left.prerelease === right.prerelease) return 0;

  // Релиз без prerelease старше любого prerelease той же версии.
  if (left.prerelease === null) return 1;
  if (right.prerelease === null) return -1;

  return left.prerelease < right.prerelease ? -1 : 1;
}

/** Сравнение версий по строкам: некорректные строки уезжают в конец списка. */
export function compareVersionStrings(left: string, right: string): -1 | 0 | 1 {
  const parsedLeft = parseVersion(left);
  const parsedRight = parseVersion(right);

  if (parsedLeft === null && parsedRight === null) return 0;
  if (parsedLeft === null) return -1;
  if (parsedRight === null) return 1;

  return compareVersions(parsedLeft, parsedRight);
}
