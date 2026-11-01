import { IsInt, IsString, Length, Max, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class CreateCourseRequest {
  @ApiProperty({ minLength: 3, maxLength: 200, example: 'Backend on NestJS 11' })
  @IsString()
  @Length(3, 200)
  title!: string;

  @ApiProperty({ maxLength: 5000, example: 'A pragmatic, production-minded course.' })
  @IsString()
  @Length(0, 5000)
  description!: string;

  @ApiProperty({
    minimum: 0,
    maximum: 1_000_000,
    example: 4900,
    description: 'Price in cents',
  })
  @IsInt()
  @Min(0)
  @Max(1_000_000)
  priceCents!: number;
}
