import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  IsArray,
  IsBoolean,
  IsEmail,
  IsInt,
  IsOptional,
  IsString,
  MaxLength,
  ValidateNested,
} from 'class-validator';

/**
 * Quick Estimate (Slice 2b) — the fast lane. Instead of picking an existing
 * customer record, sales types a name (+ optional phone/email) and the app
 * creates the minimal customer for them. The full record can be filled in
 * later; the estimate is NOT re-entered.
 */
export class QuickCustomerDto {
  @ApiProperty({ description: 'Customer name — the only required field' })
  @IsString()
  @MaxLength(200)
  name!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(20)
  phone?: string;

  // Validated as a real email — a malformed one (e.g. "not-an-email") is not
  // just cosmetic: QBO rejects the customer with "Invalid Email Address format"
  // (breaking the sync) and can't send the estimate. Empty/whitespace is
  // normalised to undefined so an optional blank still passes.
  @ApiPropertyOptional()
  @Transform(({ value }) =>
    typeof value === 'string' && value.trim() ? value.trim() : undefined,
  )
  @IsOptional()
  @IsEmail()
  @MaxLength(200)
  email?: string;
}

/** Create a draft Sales Order from a configuration. */
export class CreateSalesOrderDto {
  @ApiPropertyOptional({
    description:
      'Existing customer id. Omit when sending quickCustomer (Quick Estimate).',
  })
  @IsOptional()
  @Type(() => String)
  @IsString()
  customerId?: string;

  @ApiPropertyOptional({
    description:
      'Quick Estimate: create a minimal customer inline (name + phone). ' +
      'Mutually exclusive with customerId.',
    type: QuickCustomerDto,
  })
  @IsOptional()
  @ValidateNested()
  @Type(() => QuickCustomerDto)
  quickCustomer?: QuickCustomerDto;

  @ApiPropertyOptional({ description: 'Mark this as a Quick Estimate' })
  @IsOptional()
  @IsBoolean()
  isQuickEstimate?: boolean;

  @ApiProperty({ description: 'Trailer model id' })
  @IsInt()
  modelId!: number;

  @ApiPropertyOptional({ description: 'Selected option ids', type: [Number] })
  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  optionIds?: number[];

  @ApiPropertyOptional({ description: 'Explicit fee ids (overrides auto-add)', type: [Number] })
  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  feeIds?: number[];

  @ApiPropertyOptional({ description: 'Auto-add the standard fee set' })
  @IsOptional()
  @IsBoolean()
  autoAddFees?: boolean;

  @ApiPropertyOptional({ description: 'Payment terms free text' })
  @IsOptional()
  @IsString()
  terms?: string;

  // ── Build spec (flows into the trailer on convert) ────────────────────────

  @ApiPropertyOptional({ description: 'Paint colour' })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  color?: string;

  @ApiPropertyOptional({ description: 'Physical size in feet (e.g. "16")' })
  @IsOptional()
  @IsString()
  @MaxLength(10)
  sizeFt?: string;

  @ApiPropertyOptional({ description: 'Build / options notes for the shop' })
  @IsOptional()
  @IsString()
  optionsNotes?: string;

  @ApiPropertyOptional({ description: 'Special build instructions / note' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  specialNote?: string;

  @ApiPropertyOptional({ description: 'True when building for stock inventory' })
  @IsOptional()
  @IsBoolean()
  isStockBuild?: boolean;

  @ApiPropertyOptional({
    description: 'Destination yard when isStockBuild=true',
  })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  stockLocationId?: number;
}

/** Preview a configuration's composed lines + subtotal without persisting. */
export class PreviewSalesOrderDto {
  @ApiProperty()
  @IsInt()
  modelId!: number;

  @ApiPropertyOptional({ type: [Number] })
  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  optionIds?: number[];

  @ApiPropertyOptional({ type: [Number] })
  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  feeIds?: number[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  autoAddFees?: boolean;
}
