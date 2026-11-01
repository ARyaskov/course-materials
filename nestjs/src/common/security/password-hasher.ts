import * as argon2 from 'argon2';

/**
 * Argon2id parameters, sized so one hash costs roughly 100–500 ms of server
 * time: slow enough to make offline cracking expensive, fast enough for login.
 * OWASP's current recommendation for new projects.
 */
const ARGON2_OPTIONS = {
  type: argon2.argon2id,
  memoryCost: 19456, // 19 MiB
  timeCost: 2,
  parallelism: 1,
} satisfies argon2.HashOptions;

/** Hashes a plaintext password. The salt is generated and embedded by argon2. */
export function hashPassword(plain: string): Promise<string> {
  return argon2.hash(plain, ARGON2_OPTIONS);
}

/**
 * Verifies a password against a stored hash. A malformed or unknown hash format
 * is a failed verification, never a thrown error — that would turn a bad
 * password into a 500.
 */
export async function verifyPassword(hash: string, plain: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, plain);
  } catch {
    return false;
  }
}
