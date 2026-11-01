import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import type { AuthUser, JwtPayload } from './auth-user';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>('jwt.secret') ?? '',
    });
  }

  validate(payload: JwtPayload): AuthUser {
    // Refresh tokens must not be accepted as access tokens.
    if (payload.type !== 'access') {
      throw new UnauthorizedException('Invalid token type');
    }
    return { userId: payload.sub, email: payload.email, role: payload.role };
  }
}
