import {
  IsInt,
  IsEnum,
  IsOptional,
  IsNumber,
  IsString,
  Min,
  MaxLength,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { DeliveryTypeDto } from './query-deliveries.dto';

export class CreateDeliveryDto {
  @ApiProperty({ description: 'FK to trailers — trailer must be ready_for_delivery' })
  @IsInt()
  @Type(() => Number)
  trailerId!: number;

  @ApiProperty({ enum: DeliveryTypeDto })
  @IsEnum(DeliveryTypeDto)
  deliveryType!: DeliveryTypeDto;

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

  @ApiPropertyOptional({ description: 'Customer delivery address for single_pull' })
  @IsOptional()
  @IsString()
  customerDeliveryAddress?: string;

  @ApiPropertyOptional({ description: 'Contact phone for this delivery (driver SMS)' })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  contactPhone?: string;

  @ApiPropertyOptional({ description: 'Balance due from customer' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Type(() => Number)
  balanceDue?: number;

  @ApiPropertyOptional({ description: 'FK to delivery_batches' })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  deliveryBatchId?: number;

  // --- factory_pickup only -------------------------------------------------
  // A factory pickup is recorded in one step: the customer collects the
  // trailer at the factory, so the delivery is created already completed.
  @ApiPropertyOptional({ description: 'factory_pickup: who collected the trailer' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  pickedUpByName?: string;

  @ApiPropertyOptional({ description: 'factory_pickup: balance collected at pickup' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Type(() => Number)
  paymentCollected?: number;
}
