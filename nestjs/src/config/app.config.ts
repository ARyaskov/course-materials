import { databaseConfig } from './database.config';
import { redisConfig } from './redis.config';
import { jwtConfig } from './jwt.config';
import { securityConfig } from './security.config';

/** Namespaced configs loaded into ConfigModule via `load`. */
export const configurations = [databaseConfig, redisConfig, jwtConfig, securityConfig];

export interface AppConfig {
  database: ReturnType<typeof databaseConfig>;
  redis: ReturnType<typeof redisConfig>;
  jwt: ReturnType<typeof jwtConfig>;
  security: ReturnType<typeof securityConfig>;
}
