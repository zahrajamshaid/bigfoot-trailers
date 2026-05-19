import {
  IsString,
  IsInt,
  IsOptional,
  IsEnum,
  MaxLength,
  IsNotEmpty,
  Min,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export enum QcSeriesScopeDto {
  XP = 'xp',
  YETI = 'yeti',
  DECK_OVER = 'deck_over',
  GOOSENECK_DUMP = 'gooseneck_dump',
  ALL = 'all',
}

export class CreateChecklistItemDto {
  @ApiProperty({ description: 'FK to departments — must be a QC department' })
  @IsInt()
  @Type(() => Number)
  departmentId!: number;

  @ApiPropertyOptional({
    description: 'Series scope for this checklist item',
    default: 'all',
  })
  @IsOptional()
  @IsEnum(QcSeriesScopeDto)
  appliesToSeries?: QcSeriesScopeDto;

  @ApiProperty({ description: 'Label text for the checklist item' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(300)
  itemLabel!: string;

  @ApiPropertyOptional({
    description: 'Sort order within the department checklist',
    default: 0,
  })
  @IsOptional()
  @IsInt()
  @Min(0)
  @Type(() => Number)
  sortOrder?: number;

  @ApiPropertyOptional({
    description:
      'Addon-gating key. NULL = always shown; "*" = shown when trailer has any addon; otherwise matches trailer_addons.addon_name.',
    maxLength: 60,
  })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  requiresAddonKey?: string;
}
