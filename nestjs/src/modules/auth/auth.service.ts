import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { UsersService } from '../users/users.service';
import { verifyPassword } from '../../common/security/password-hasher';
import { DomainException } from '../../common/errors/domain-error';
import type { User } from '../users/domain/user';
import type { AuthTokens } from './dto/auth.response';
import type { JwtPayload } from './auth-user';

@Injectable()
export class AuthService {
  constructor(
    private readonly users: UsersService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async validateUser(email: string, password: string): Promise<User> {
    const found = await this.users.findByEmailWithCredentials(email);
    if (!found) {
      throw new DomainException({ code: 'INVALID_CREDENTIALS' });
    }
    const ok = await verifyPassword(found.passwordHash, password);
    if (!ok) {
      throw new DomainException({ code: 'INVALID_CREDENTIALS' });
    }
    const { passwordHash: _omit, ...user } = found;
    return user;
  }

  async login(email: string, password: string): Promise<AuthTokens> {
    const user = await this.validateUser(email, password);
    return this.issueTokens(user);
  }

  async refresh(refreshToken: string): Promise<AuthTokens> {
    let payload: JwtPayload;
    try {
      payload = await this.jwt.verifyAsync<JwtPayload>(refreshToken, {
        secret: this.config.get<string>('jwt.secret') ?? '',
      });
    } catch {
      throw new DomainException({ code: 'INVALID_REFRESH_TOKEN' });
    }
    if (payload.type !== 'refresh') {
      throw new DomainException({ code: 'INVALID_REFRESH_TOKEN' });
    }
    const user = await this.users.findById(payload.sub);
    if (!user) {
      throw new DomainException({ code: 'INVALID_REFRESH_TOKEN' });
    }
    return this.issueTokens(user);
  }

  private async issueTokens(user: User): Promise<AuthTokens> {
    const secret = this.config.get<string>('jwt.secret') ?? '';
    const accessTtl = this.config.get<string>('jwt.accessTtl') ?? '15m';
    const refreshTtl = this.config.get<string>('jwt.refreshTtl') ?? '30d';

    const base = { sub: user.id as string, email: user.email, role: user.role };
    // `expiresIn` is typed by `ms` as a template-literal StringValue; values come
    // from configuration as plain strings, so we assert them through.
    const accessToken = await this.jwt.signAsync(
      { ...base, type: 'access' as const },
      { secret, expiresIn: accessTtl as unknown as number },
    );
    const refreshToken = await this.jwt.signAsync(
      { ...base, type: 'refresh' as const },
      { secret, expiresIn: refreshTtl as unknown as number },
    );

    return { accessToken, refreshToken, tokenType: 'Bearer', expiresIn: accessTtl };
  }
}
