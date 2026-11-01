import { registerAs } from '@nestjs/config';

/**
 * CORS and login rate-limit policy. Origins are an explicit allow-list — never
 * `*` together with credentials — and the login budget is the first line of
 * defence against password brute-forcing.
 */
export const securityConfig = registerAs('security', () => ({
  corsOrigins: (process.env.CORS_ORIGINS ?? 'http://localhost:5173')
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0),
  login: {
    /** Attempts allowed per client IP within one minute. */
    perIp: Number(process.env.LOGIN_RATE_LIMIT_PER_IP ?? 5),
    perIpWindowSeconds: 60,
    /** Attempts allowed per email address within one hour. */
    perEmail: Number(process.env.LOGIN_RATE_LIMIT_PER_EMAIL ?? 10),
    perEmailWindowSeconds: 60 * 60,
  },
}));

export type SecurityConfig = ReturnType<typeof securityConfig>;
