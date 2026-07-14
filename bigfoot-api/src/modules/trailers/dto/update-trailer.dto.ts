import {
  IsBoolean,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';

export enum TrailerStatusDto {
  PENDING_PRODUCTION = 'pending_production',
  IN_PRODUCTION = 'in_production',
  READY_FOR_DELIVERY = 'ready_for_delivery',
  IN_TRANSIT = 'in_transit',
  DELIVERED = 'delivered',
  ON_HOLD = 'on_hold',
}

export class UpdateTrailerDto {
  @ApiPropertyOptional({ description: 'SO number (must remain unique)' })
  @IsOptional()
  @IsString()
  @MaxLength(30)
  soNumber?: string;

  @ApiPropertyOptional({ description: 'FK to trailer_models' })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  trailerModelId?: number;

  @ApiPropertyOptional({
    description:
      'Vehicle Identification Number — exactly 17 characters, excluding the ' +
      'letters I, O and Q. Unique across trailers. Send "" to clear it.',
    example: '1BF12345XYZ678901',
  })
  @IsOptional()
  @Transform(({ value }) =>
    typeof value === 'string' ? value.trim().toUpperCase() : value,
  )
  @IsString()
  @Matches(/^([A-HJ-NPR-Z0-9]{17})?$/, {
    message:
      'VIN must be exactly 17 characters (letters and digits, excluding I, O and Q)',
  })
  vinNumber?: string;

  @ApiPropertyOptional({ description: 'FK to customers (null clears the link)' })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  customerId?: number | null;

  @ApiPropertyOptional({
    description:
      'Free-text customer / buyer name. Non-empty marks the trailer sold; ' +
      'empty string clears it back to available.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  soldToName?: string;

  @ApiPropertyOptional({ description: 'Paint color' })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  color?: string;

  @ApiPropertyOptional({ description: 'Physical size (e.g. "16ft")' })
  @IsOptional()
  @IsString()
  @MaxLength(10)
  sizeFt?: string;

  @ApiPropertyOptional({ description: 'Special instructions / add-on notes' })
  @IsOptional()
  @IsString()
  optionsNotes?: string;

  @ApiPropertyOptional({ description: 'Short free-form note (max 500 chars)' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  specialNote?: string;

  @ApiPropertyOptional({ description: 'True if building for inventory' })
  @IsOptional()
  @IsBoolean()
  isStockBuild?: boolean;

  @ApiPropertyOptional({
    description: 'Destination stock location ID when isStockBuild=true',
  })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  stockLocationId?: number;

  @ApiPropertyOptional({ description: 'QuickBooks SO object ID for future sync' })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  qbSoId?: string;

  @ApiPropertyOptional({ enum: TrailerStatusDto, description: 'Trailer status' })
  @IsOptional()
  @IsEnum(TrailerStatusDto)
  status?: TrailerStatusDto;
}
