import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { UsersModule } from '../users/users.module';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';
import { RolesGuard } from './roles.guard';
import { LoginRateLimitInterceptor } from './login-rate-limit.interceptor';

@Module({
  imports: [
    UsersModule,
    PassportModule,
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get<string>('jwt.secret') ?? '',
        // expiresIn is typed by `ms` as a template-literal StringValue; config
        // returns a widened string, so we assert the configured value.
        signOptions: {
          expiresIn: (config.get<string>('jwt.accessTtl') ?? '15m') as `${number}m`,
        },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy, RolesGuard, LoginRateLimitInterceptor],
  exports: [AuthService, RolesGuard],
})
export class AuthModule {}
