import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { EnrollmentService } from './enrollment.service';
import { CreateEnrollmentRequest } from './dto/create-enrollment.request';
import type { EnrollmentResponse } from './dto/enrollment.response';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import type { AuthUser } from '../auth/auth-user';

@ApiTags('enrollment')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('enrollments')
export class EnrollmentController {
  constructor(private readonly service: EnrollmentService) {}

  @Post()
  enroll(
    @CurrentUser() user: AuthUser,
    @Body() body: CreateEnrollmentRequest,
  ): Promise<EnrollmentResponse> {
    return this.service.enroll(user.userId, body.courseId);
  }

  @Get('me')
  listMine(@CurrentUser() user: AuthUser): Promise<EnrollmentResponse[]> {
    return this.service.listMine(user.userId);
  }

  @Delete(':courseId')
  @HttpCode(204)
  unenroll(
    @CurrentUser() user: AuthUser,
    @Param('courseId', ParseUUIDPipe) courseId: string,
  ): Promise<void> {
    return this.service.unenroll(user.userId, courseId);
  }
}
