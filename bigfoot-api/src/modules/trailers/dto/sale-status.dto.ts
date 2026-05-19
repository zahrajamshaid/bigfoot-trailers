import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export enum TrailerSaleStatusDto {
  AVAILABLE = 'available',
  SALE_PENDING = 'sale_pending',
  SOLD = 'sold',
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
}
