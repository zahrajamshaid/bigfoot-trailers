import { IsOptional, IsNumber, IsEnum, IsArray, IsString, IsBoolean, Min } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export enum PaymentMethodDto {
  CASHIERS_CHECK = 'cashiers_check',
  DEBIT = 'debit',
  CASH = 'cash',
}

export class CompleteDeliveryDto {
  @ApiPropertyOptional({ description: 'Payment amount collected' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Type(() => Number)
  paymentCollected?: number;

  @ApiPropertyOptional({ enum: PaymentMethodDto })
  @IsOptional()
  @IsEnum(PaymentMethodDto)
  paymentMethod?: PaymentMethodDto;

  @ApiPropertyOptional({ description: 'Storage keys of proof-of-delivery photos' })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  photoStorageKeys?: string[];

  @ApiPropertyOptional({ description: 'Whether T&C were accepted' })
  @IsOptional()
  @IsBoolean()
  tcAccepted?: boolean;

  @ApiPropertyOptional({ description: 'Signature storage URL' })
  @IsOptional()
  @IsString()
  signatureUrl?: string;

  @ApiPropertyOptional({ description: 'GPS latitude at delivery' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 7 })
  @Type(() => Number)
  gpsLat?: number;

  @ApiPropertyOptional({ description: 'GPS longitude at delivery' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 7 })
  @Type(() => Number)
  gpsLng?: number;
}
