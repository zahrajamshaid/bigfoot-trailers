import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString } from 'class-validator';

export class RefreshDto {
  @ApiProperty({ description: 'The refresh token received from login or previous refresh' })
  @IsString()
  @IsNotEmpty()
  refreshToken!: string;
}
