import {
  IsOptional,
  IsInt,
  IsString,
  IsEnum,
  IsNotEmpty,
  IsArray,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export enum BatchTypeDto {
  DEALER = 'dealer',
  BF_LOCATION = 'bf_location',
}

export class CreateBatchDto {
  @ApiProperty({ description: 'Unique batch number' })
  @IsString()
  @IsNotEmpty()
  batchNumber!: string;

  @ApiProperty({ enum: BatchTypeDto })
  @IsEnum(BatchTypeDto)
  batchType!: BatchTypeDto;

  @ApiPropertyOptional({ description: 'FK to users (driver)' })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  driverUserId?: number;

  @ApiPropertyOptional({ description: 'FK to locations (destination)' })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  destinationLocationId?: number;

  @ApiPropertyOptional({
    description: 'Destination name (for dealers not in locations table)',
  })
  @IsOptional()
  @IsString()
  destinationName?: string;

  @ApiPropertyOptional({
    description:
      'Trailer IDs to add to the batch on creation — each must be ready_for_delivery',
    type: [Number],
  })
  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  @Type(() => Number)
  trailerIds?: number[];
}
