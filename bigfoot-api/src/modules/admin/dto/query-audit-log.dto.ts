import { IsOptional, IsString, IsDateString } from 'class-validator';
import { Type } from 'class-transformer';
import { ApiPropertyOptional } from '@nestjs/swagger';

export class QueryAuditLogDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  entityType?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  entityId?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  userId?: number;

  @ApiPropertyOptional({ description: 'ISO date string — start of range' })
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional({ description: 'ISO date string — end of range' })
  @IsOptional()
  @IsDateString()
  to?: string;

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @Type(() => Number)
  page?: number;

  @ApiPropertyOptional({ default: 50 })
  @IsOptional()
  @Type(() => Number)
  limit?: number;

  /// Free-text filter. Numeric input is treated as an SO number — the
  /// service resolves it to the trailer + its dependent rows (QC
  /// inspections, production steps, deliveries) so a search for "6715"
  /// catches every entity the trailer ever touched. Non-numeric input
  /// matches against user.fullName and action (case-insensitive
  /// substring) so admin can grep for "Dev QC Inspector" or "jumped".
  @ApiPropertyOptional({
    description: 'SO number, user name, or action verb (case-insensitive)',
  })
  @IsOptional()
  @IsString()
  q?: string;
}
