import { Body, Controller, HttpCode, Post, UseInterceptors } from '@nestjs/common';
import { ApiOkResponse, ApiTags, ApiTooManyRequestsResponse } from '@nestjs/swagger';
import { LoginRateLimitInterceptor } from './login-rate-limit.interceptor';
import { AuthService } from './auth.service';
import { LoginRequest } from './dto/login.request';
import { RefreshRequest } from './dto/refresh.request';
import type { AuthTokens } from './dto/auth.response';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('login')
  @HttpCode(200)
  @UseInterceptors(LoginRateLimitInterceptor)
  @ApiOkResponse({ description: 'Access + refresh tokens' })
  @ApiTooManyRequestsResponse({ description: 'Too many login attempts; see Retry-After' })
  login(@Body() body: LoginRequest): Promise<AuthTokens> {
    return this.auth.login(body.email, body.password);
  }

  @Post('refresh')
  @HttpCode(200)
  @ApiOkResponse({ description: 'A fresh pair of tokens' })
  refresh(@Body() body: RefreshRequest): Promise<AuthTokens> {
    return this.auth.refresh(body.refreshToken);
  }
}
