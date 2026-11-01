import { PartialType } from '@nestjs/mapped-types';
import { CreateCourseRequest } from './create-course.request';

/** All fields optional — PATCH semantics. */
export class UpdateCourseRequest extends PartialType(CreateCourseRequest) {}
