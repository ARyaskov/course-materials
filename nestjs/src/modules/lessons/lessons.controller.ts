import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { LessonsService } from './lessons.service';
import { CreateLessonRequest } from './dto/create-lesson.request';
import { UpdateLessonRequest } from './dto/update-lesson.request';
import type { LessonResponse } from './dto/lesson.response';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { CurrentUser } from '../auth/current-user.decorator';
import type { AuthUser } from '../auth/auth-user';

@ApiTags('lessons')
@Controller('courses/:courseId/lessons')
export class LessonsController {
  constructor(private readonly service: LessonsService) {}

  @Get()
  list(@Param('courseId', ParseUUIDPipe) courseId: string): Promise<LessonResponse[]> {
    return this.service.list(courseId);
  }

  @Get(':lessonId')
  one(
    @Param('courseId', ParseUUIDPipe) courseId: string,
    @Param('lessonId', ParseUUIDPipe) lessonId: string,
  ): Promise<LessonResponse> {
    return this.service.getOne(courseId, lessonId);
  }

  @Post()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('instructor', 'admin')
  @ApiBearerAuth()
  create(
    @CurrentUser() user: AuthUser,
    @Param('courseId', ParseUUIDPipe) courseId: string,
    @Body() body: CreateLessonRequest,
  ): Promise<LessonResponse> {
    return this.service.create(user, courseId, body);
  }

  @Patch(':lessonId')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('instructor', 'admin')
  @ApiBearerAuth()
  update(
    @CurrentUser() user: AuthUser,
    @Param('courseId', ParseUUIDPipe) courseId: string,
    @Param('lessonId', ParseUUIDPipe) lessonId: string,
    @Body() body: UpdateLessonRequest,
  ): Promise<LessonResponse> {
    return this.service.update(user, courseId, lessonId, body);
  }

  @Delete(':lessonId')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('instructor', 'admin')
  @ApiBearerAuth()
  @HttpCode(204)
  remove(
    @CurrentUser() user: AuthUser,
    @Param('courseId', ParseUUIDPipe) courseId: string,
    @Param('lessonId', ParseUUIDPipe) lessonId: string,
  ): Promise<void> {
    return this.service.remove(user, courseId, lessonId);
  }
}
