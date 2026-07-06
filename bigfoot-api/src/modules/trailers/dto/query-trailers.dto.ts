import {
  IsOptional,
  IsInt,
  IsBoolean,
  IsEnum,
  Min,
  Max,
  IsString,
  IsDateString,
} from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type, Transform } from 'class-transformer';
import { TrailerStatusDto } from './update-trailer.dto';
import { TrailerSaleStatusDto } from './sale-status.dto';

export enum TrailerSeriesDto {
  XP = 'xp',
  YETI = 'yeti',
  DECK_OVER = 'deck_over',
  GOOSENECK_DUMP = 'gooseneck_dump',
  // Inventory-only models (Triple Crown / Enclosed / Misc). Lets the
  // trailer list filter by these in admin / sales views.
  INVENTORY = 'inventory',
  // Gooseneck Yeti — gooseneck_dump workflow with YETI_FIN at step 3.
  GOOSENECK_YETI = 'gooseneck_yeti',
  // CXP — small pull-behind that runs 1-for-1 through the gooseneck
  // workflow (including the GN_FIN + QC_2 bypass and PAINT_B default),
  // but kept as its own series so reporting / filters treat it
  // distinctly.
  CXP = 'cxp',
}

export class QueryTrailersDto {
  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Type(() => Number)
  page?: number;

  @ApiPropertyOptional({ default: 25 })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  @Type(() => Number)
  limit?: number;

  @ApiPropertyOptional({ enum: TrailerStatusDto })
  @IsOptional()
  @IsEnum(TrailerStatusDto)
  status?: TrailerStatusDto;

  @ApiPropertyOptional({ enum: TrailerSeriesDto })
  @IsOptional()
  @IsEnum(TrailerSeriesDto)
  series?: TrailerSeriesDto;

  @ApiPropertyOptional({ enum: TrailerSaleStatusDto })
  @IsOptional()
  @IsEnum(TrailerSaleStatusDto)
  saleStatus?: TrailerSaleStatusDto;

  @ApiPropertyOptional({ description: 'Filter by customer ID' })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  customerId?: number;

  @ApiPropertyOptional({ description: 'Filter by current location (yard) ID' })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  locationId?: number;

  @ApiPropertyOptional({
    description:
      'Filter by current location code. Matches Location.code (e.g. ' +
      'MULBERRY, JACKSONVILLE). Independent of locationId and ' +
      'intendedStockLocationCode — combining the two gives an AND match ' +
      '("currently at A, destined for B"), which is what the Mulberry-' +
      'ready-to-ship drilldowns need.',
  })
  @IsOptional()
  @IsString()
  currentLocationCode?: string;

  @ApiPropertyOptional({
    description:
      'Filter by intended stock location code. Matches ' +
      'Location.code on the trailer.intendedStockLocation relation. Used by ' +
      'the dashboard tile that lists stock builds at Mulberry waiting to be ' +
      'shipped to a specific yard.',
  })
  @IsOptional()
  @IsString()
  intendedStockLocationCode?: string;

  @ApiPropertyOptional({ description: 'Filter hot trailers only' })
  @IsOptional()
  @IsBoolean()
  @Transform(({ value }) => value === 'true' || value === true)
  isHot?: boolean;

  @ApiPropertyOptional({
    description:
      'Filter by trailer.isStockBuild. `true` = stock builds only, ' +
      '`false` = customer orders only, omitted = both. Used by the ' +
      'dashboard "Customer Pickups @ Mulberry" tile.',
  })
  @IsOptional()
  @IsBoolean()
  @Transform(({ value }) => {
    if (value === undefined) return undefined;
    if (value === true || value === 'true') return true;
    if (value === false || value === 'false') return false;
    return value;
  })
  isStockBuild?: boolean;

  @ApiPropertyOptional({
    description:
      'Exclude trailers that already have an open (scheduled / in-transit) delivery',
  })
  @IsOptional()
  @IsBoolean()
  @Transform(({ value }) => value === 'true' || value === true)
  excludeOpenDeliveries?: boolean;

  @ApiPropertyOptional({ description: 'Search by SO number or customer name' })
  @IsOptional()
  @IsString()
  search?: string;

  @ApiPropertyOptional({
    description:
      'Only return trailers that have at least one delivered Delivery at or ' +
      'after this timestamp. Used by the "Completed this week" drilldown. ' +
      'ISO 8601.',
    example: '2026-05-26T00:00:00.000Z',
  })
  @IsOptional()
  @IsDateString()
  completedSince?: string;
}
