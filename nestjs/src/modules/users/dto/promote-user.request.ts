import { IsIn } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import type { UserRole } from '../domain/user';

export class PromoteUserRequest {
  @ApiProperty({ enum: ['student', 'instructor', 'admin'], example: 'instructor' })
  @IsIn(['student', 'instructor', 'admin'])
  role!: UserRole;
}
