import { z } from 'zod';

/**
 * Single source of truth for environment variables.
 * Used by ConfigModule's `validate` so the app fails fast on misconfiguration.
 */
export const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url().default('redis://localhost:6379'),
  JWT_SECRET: z.string().min(32),
  JWT_ACCESS_TTL: z.string().default('15m'),
  JWT_REFRESH_TTL: z.string().default('30d'),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),

  /** Comma-separated list of browser origins allowed to call the API. */
  CORS_ORIGINS: z.string().default('http://localhost:5173'),

  /** Login brute-force budget: attempts per IP per minute / per email per hour. */
  LOGIN_RATE_LIMIT_PER_IP: z.coerce.number().int().positive().default(5),
  LOGIN_RATE_LIMIT_PER_EMAIL: z.coerce.number().int().positive().default(10),
});

export type Env = z.infer<typeof envSchema>;

/**
 * Parses raw `process.env`. Unknown keys are stripped; a readable error is
 * thrown when validation fails so startup logs point at the offending var.
 */
export function validateEnv(raw: Record<string, unknown>): Env {
  const result = envSchema.safeParse(raw);
  if (!result.success) {
    const issues = result.error.issues
      .map((i) => `  - ${i.path.join('.') || '(root)'}: ${i.message}`)
      .join('\n');
    throw new Error(`Invalid environment variables:\n${issues}`);
  }
  return result.data;
}
