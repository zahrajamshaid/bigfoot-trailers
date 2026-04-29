import { IsString, IsOptional, MaxLength, IsEnum } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';

export enum TrailerStatusDto {
  PENDING_PRODUCTION = 'pending_production',
  IN_PRODUCTION = 'in_production',
  READY_FOR_DELIVERY = 'ready_for_delivery',
  IN_TRANSIT = 'in_transit',
  DELIVERED = 'delivered',
  ON_HOLD = 'on_hold',
}

export class UpdateTrailerDto {
  @ApiPropertyOptional({ description: 'Paint color' })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  color?: string;

  @ApiPropertyOptional({ description: 'Special instructions / add-on notes' })
  @IsOptional()
  @IsString()
  optionsNotes?: string;

  @ApiPropertyOptional({ enum: TrailerStatusDto, description: 'Trailer status' })
  @IsOptional()
  @IsEnum(TrailerStatusDto)
  status?: TrailerStatusDto;
}
