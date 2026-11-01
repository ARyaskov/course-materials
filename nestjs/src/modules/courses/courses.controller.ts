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
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CoursesService } from './courses.service';
import { CreateCourseRequest } from './dto/create-course.request';
import { UpdateCourseRequest } from './dto/update-course.request';
import { ListCoursesQuery } from './dto/list-courses.query';
import type { CourseResponse } from './dto/course.response';
import type { Page } from '../../common/types/page';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { CurrentUser } from '../auth/current-user.decorator';
import type { AuthUser } from '../auth/auth-user';

@ApiTags('courses')
@Controller('courses')
export class CoursesController {
  constructor(private readonly service: CoursesService) {}

  @Get()
  list(@Query() query: ListCoursesQuery): Promise<Page<CourseResponse>> {
    return this.service.list(query);
  }

  @Get(':id')
  one(@Param('id', ParseUUIDPipe) id: string): Promise<CourseResponse> {
    return this.service.getById(id);
  }

  @Post()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('instructor', 'admin')
  @ApiBearerAuth()
  create(
    @CurrentUser() user: AuthUser,
    @Body() body: CreateCourseRequest,
  ): Promise<CourseResponse> {
    return this.service.create(user.userId, body);
  }

  @Patch(':id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('instructor', 'admin')
  @ApiBearerAuth()
  update(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: UpdateCourseRequest,
  ): Promise<CourseResponse> {
    return this.service.update(user, id, body);
  }

  @Post(':id/publish')
  @HttpCode(200)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('instructor', 'admin')
  @ApiBearerAuth()
  publish(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<CourseResponse> {
    // 200, not 201: publishing changes an existing course, it creates nothing.
    return this.service.publish(user, id);
  }

  @Delete(':id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('instructor', 'admin')
  @ApiBearerAuth()
  @HttpCode(204)
  remove(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<void> {
    return this.service.remove(user, id);
  }
}
