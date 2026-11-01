import { IsUUID } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class CreateEnrollmentRequest {
  @ApiProperty({ format: 'uuid', description: 'The course to enroll in' })
  @IsUUID()
  courseId!: string;
}
