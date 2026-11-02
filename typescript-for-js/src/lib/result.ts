export type Result<T, E> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: E };

export function ok<T>(value: T): Result<T, never> {
  return { ok: true, value };
}

export function err<E>(error: E): Result<never, E> {
  return { ok: false, error };
}

export function mapResult<T, R, E>(
  result: Result<T, E>,
  transform: (value: T) => R,
): Result<R, E> {
  return result.ok ? ok(transform(result.value)) : result;
}

export function flatMapResult<T, R, E>(
  result: Result<T, E>,
  next: (value: T) => Result<R, E>,
): Result<R, E> {
  return result.ok ? next(result.value) : result;
}

export function mapError<T, E, F>(result: Result<T, E>, transform: (error: E) => F): Result<T, F> {
  return result.ok ? result : err(transform(result.error));
}

export function unwrapOr<T, E>(result: Result<T, E>, fallback: T): T {
  return result.ok ? result.value : fallback;
}

export function unwrapOrThrow<T, E>(result: Result<T, E>, describe: (error: E) => string): T {
  if (!result.ok) throw new Error(describe(result.error));
  return result.value;
}

export async function tryAsync<T>(
  operation: () => Promise<T>,
): Promise<Result<T, Error>> {
  try {
    return ok(await operation());
  } catch (caught) {
    return err(caught instanceof Error ? caught : new Error(String(caught)));
  }
}

export function trySync<T>(operation: () => T): Result<T, Error> {
  try {
    return ok(operation());
  } catch (caught) {
    return err(caught instanceof Error ? caught : new Error(String(caught)));
  }
}
