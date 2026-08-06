import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsIn,
  IsISO8601,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';
import {
  ANNOUNCEMENT_FREQUENCIES,
  AnnouncementFrequency,
} from './create-announcement.dto';

export class UpdateAnnouncementDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  title?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  body?: string;

  @ApiPropertyOptional({
    description: 'How often it re-appears: once | every_login | daily | weekly.',
    enum: ANNOUNCEMENT_FREQUENCIES,
  })
  @IsOptional()
  @IsIn(ANNOUNCEMENT_FREQUENCIES)
  frequency?: AnnouncementFrequency;

  @ApiPropertyOptional({
    description:
      "Soft toggle — false hides the modal from any users that haven't acked yet.",
  })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @ApiPropertyOptional({
    description: 'ISO datetime after which the announcement is auto-deactivated.',
  })
  @IsOptional()
  @IsISO8601({ strict: false })
  expiresAt?: string;
}
