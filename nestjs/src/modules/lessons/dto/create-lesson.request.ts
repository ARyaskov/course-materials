import { IsInt, IsOptional, IsString, Length, Min } from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class CreateLessonRequest {
  @ApiProperty({
    minLength: 3,
    maxLength: 200,
    example: 'Event loop, который наконец понятен',
  })
  @IsString()
  @Length(3, 200)
  title!: string;

  @ApiPropertyOptional({ maxLength: 20000 })
  @IsOptional()
  @IsString()
  @Length(0, 20000)
  content?: string;

  @ApiPropertyOptional({
    minimum: 1,
    description: 'Position within the course; auto-appended if omitted',
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  position?: number;
}
