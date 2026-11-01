import { IsString, MinLength } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class RefreshRequest {
  @ApiProperty({ description: 'A refresh token previously issued by /auth/login' })
  @IsString()
  @MinLength(10)
  refreshToken!: string;
}
