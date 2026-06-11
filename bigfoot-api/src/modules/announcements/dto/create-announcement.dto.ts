import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsISO8601,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

export class CreateAnnouncementDto {
  @ApiPropertyOptional({ description: 'Short headline shown in the modal title.' })
  @IsOptional()
  @IsString()
  @MaxLength(120)
  title?: string;

  @ApiProperty({ description: 'The message body shown to every user.' })
  @IsString()
  @IsNotEmpty()
  @MinLength(1)
  @MaxLength(2000)
  body!: string;

  /// Optional expiry — past this point the modal stops appearing for new
  /// users even if no one acked it. Date+time (`YYYY-MM-DDTHH:mm:ssZ`).
  @ApiPropertyOptional({
    description: 'ISO datetime after which the announcement is auto-deactivated.',
    example: '2026-07-01T18:00:00Z',
  })
  @IsOptional()
  @IsISO8601({ strict: false })
  expiresAt?: string;
}
