import { IsOptional, IsInt, IsEnum, IsDateString } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export enum DeliveryStatusDto {
  SCHEDULED = 'scheduled',
  IN_TRANSIT = 'in_transit',
  DELIVERED = 'delivered',
  FAILED = 'failed',
}

export enum DeliveryTypeDto {
  FACTORY_PICKUP = 'factory_pickup',
  STACK_TO_DEALER = 'stack_to_dealer',
  STACK_TO_LOCATION = 'stack_to_location',
  SINGLE_PULL = 'single_pull',
}

export class QueryDeliveriesDto {
  @ApiPropertyOptional({ enum: DeliveryStatusDto })
  @IsOptional()
  @IsEnum(DeliveryStatusDto)
  status?: DeliveryStatusDto;

  @ApiPropertyOptional({ enum: DeliveryTypeDto })
  @IsOptional()
  @IsEnum(DeliveryTypeDto)
  deliveryType?: DeliveryTypeDto;

  @ApiPropertyOptional({ description: 'Filter by driver user ID' })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  driverUserId?: number;

  @ApiPropertyOptional({ description: 'Start of date range (YYYY-MM-DD)' })
  @IsOptional()
  @IsDateString()
  dateFrom?: string;

  @ApiPropertyOptional({ description: 'End of date range (YYYY-MM-DD)' })
  @IsOptional()
  @IsDateString()
  dateTo?: string;
}
