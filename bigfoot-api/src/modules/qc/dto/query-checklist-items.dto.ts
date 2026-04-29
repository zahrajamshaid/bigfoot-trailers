import { IsOptional, IsInt, IsEnum } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { QcSeriesScopeDto } from './create-checklist-item.dto';

export class QueryChecklistItemsDto {
  @ApiPropertyOptional({ description: 'Filter by QC department ID' })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  departmentId?: number;

  @ApiPropertyOptional({ description: 'Filter by series scope' })
  @IsOptional()
  @IsEnum(QcSeriesScopeDto)
  seriesScope?: QcSeriesScopeDto;

  @ApiPropertyOptional({
    description:
      'Trailer ID — when set, the response includes option-gated items whose requires_addon_key matches one of the trailer\'s addons (plus "*" wildcard items when any addon is present).',
  })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  trailerId?: number;
}
