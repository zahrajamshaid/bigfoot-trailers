import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsOptional, IsString, MaxLength } from 'class-validator';

export class PushTokenDto {
  @ApiProperty({ description: 'FCM device push token' })
  @IsString()
  @IsNotEmpty()
  pushToken!: string;

  @ApiPropertyOptional({ description: 'Human-readable device label', example: 'iPhone 15 Pro' })
  @IsString()
  @IsOptional()
  @MaxLength(100)
  deviceLabel?: string;
}
