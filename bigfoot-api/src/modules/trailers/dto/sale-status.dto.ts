import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export enum TrailerSaleStatusDto {
  AVAILABLE = 'available',
  SALE_PENDING = 'sale_pending',
  SOLD = 'sold',
}

// Sales chooses, at sold-time, how the buyer will receive the trailer.
// Drives which scheduled Delivery is auto-created on the sold transition.
export enum FulfilmentType {
  // Customer comes to one of our yards to collect → factory_pickup Delivery.
  PICKUP = 'pickup',
  // We haul it out to them → single_pull (end user) or stack_to_dealer.
  DELIVERY = 'delivery',
}

export class UpdateSaleStatusDto {
  @ApiProperty({ enum: TrailerSaleStatusDto, description: 'New sale status' })
  @IsEnum(TrailerSaleStatusDto)
  saleStatus!: TrailerSaleStatusDto;

  @ApiPropertyOptional({
    description:
      'Free-text buyer name. Required when marking a trailer sold unless it ' +
      'already has a customer.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  soldToName?: string;

  @ApiPropertyOptional({
    enum: FulfilmentType,
    description:
      'When transitioning to sold, how the buyer receives the trailer. ' +
      'Auto-creates the matching scheduled Delivery. Ignored on transitions ' +
      'away from sold.',
  })
  @IsOptional()
  @IsEnum(FulfilmentType)
  fulfilmentType?: FulfilmentType;

  @ApiPropertyOptional({
    description:
      'Buyer delivery address. Used when fulfilmentType=delivery to populate ' +
      'the scheduled Delivery row. Falls back to the customer record address ' +
      "when omitted and a customer is linked.",
  })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  deliveryAddress?: string;
}
