import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsISO8601, IsOptional } from 'class-validator';

export class ActivityReportQueryDto {
  @ApiPropertyOptional({
    description: 'Start day (inclusive), YYYY-MM-DD. Defaults to 6 days ago.',
    example: '2026-08-06',
  })
  @IsOptional()
  @IsISO8601({ strict: false })
  from?: string;

  @ApiPropertyOptional({
    description: 'End day (inclusive), YYYY-MM-DD. Defaults to today.',
    example: '2026-08-12',
  })
  @IsOptional()
  @IsISO8601({ strict: false })
  to?: string;
}
