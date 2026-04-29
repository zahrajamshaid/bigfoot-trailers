import { IsOptional, IsInt, IsString, IsArray } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class UpdateBatchDto {
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

  @ApiPropertyOptional({ description: 'Destination name' })
  @IsOptional()
  @IsString()
  destinationName?: string;

  @ApiPropertyOptional({ description: 'Trailer IDs to add to the batch', type: [Number] })
  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  @Type(() => Number)
  addTrailerIds?: number[];

  @ApiPropertyOptional({ description: 'Delivery IDs to remove from the batch', type: [Number] })
  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  @Type(() => Number)
  removeDeliveryIds?: number[];
}
