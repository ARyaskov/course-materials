import { Body, Controller, Get, Param, ParseUUIDPipe, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiCreatedResponse, ApiOkResponse, ApiTags } from '@nestjs/swagger';
import { UsersService } from './users.service';
import { RegisterUserRequest } from './dto/register-user.request';
import { PromoteUserRequest } from './dto/promote-user.request';
import { toUserResponse, type UserResponse } from './dto/user.response';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { CurrentUser } from '../auth/current-user.decorator';
import type { AuthUser } from '../auth/auth-user';

@ApiTags('users')
@Controller('users')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Post('register')
  @ApiCreatedResponse({ description: 'The newly created user' })
  async register(@Body() body: RegisterUserRequest): Promise<UserResponse> {
    const user = await this.users.register(body);
    return toUserResponse(user);
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOkResponse({ description: 'The authenticated user' })
  async me(@CurrentUser() current: AuthUser): Promise<UserResponse> {
    const user = await this.users.getByIdOrThrow(current.userId);
    return toUserResponse(user);
  }

  /**
   * Grants a role. Roles are never self-assigned — the first admin is seeded,
   * and every later promotion goes through an existing admin.
   */
  @Post(':id/promote')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @ApiBearerAuth()
  @ApiCreatedResponse({ description: 'The user with the new role' })
  async promote(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: PromoteUserRequest,
  ): Promise<UserResponse> {
    const user = await this.users.promote(id, body.role);
    return toUserResponse(user);
  }
}
