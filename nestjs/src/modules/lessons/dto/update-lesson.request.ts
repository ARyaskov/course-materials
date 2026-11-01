import { PartialType } from '@nestjs/mapped-types';
import { CreateLessonRequest } from './create-lesson.request';

export class UpdateLessonRequest extends PartialType(CreateLessonRequest) {}
