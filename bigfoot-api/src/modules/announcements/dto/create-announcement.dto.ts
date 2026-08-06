import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsISO8601,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

/// How often an announcement re-surfaces for a user who has already seen it.
/// `once` is the original behaviour — show until acked, then never again.
export const ANNOUNCEMENT_FREQUENCIES = [
  'once',
  'every_login',
  'daily',
  'weekly',
] as const;
export type AnnouncementFrequency = (typeof ANNOUNCEMENT_FREQUENCIES)[number];

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

  @ApiPropertyOptional({
    description:
      'How often it re-appears for a user: once | every_login | daily | weekly.',
    enum: ANNOUNCEMENT_FREQUENCIES,
    default: 'once',
  })
  @IsOptional()
  @IsIn(ANNOUNCEMENT_FREQUENCIES)
  frequency?: AnnouncementFrequency;

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
