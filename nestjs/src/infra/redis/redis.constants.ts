/**
 * DI token for the shared ioredis client. A constant rather than a bare string
 * literal so the name can't drift and tests can swap in an in-memory double.
 */
export const REDIS_CLIENT = Symbol('REDIS_CLIENT');
