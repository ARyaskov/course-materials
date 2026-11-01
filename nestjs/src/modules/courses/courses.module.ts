import { Module } from '@nestjs/common';
import { CoursesController } from './courses.controller';
import { CoursesService } from './courses.service';
import { CoursesRepository } from './courses.repository';
import { CoursesCache } from './courses-cache';

@Module({
  controllers: [CoursesController],
  providers: [CoursesService, CoursesRepository, CoursesCache],
  exports: [CoursesService, CoursesCache],
})
export class CoursesModule {}
