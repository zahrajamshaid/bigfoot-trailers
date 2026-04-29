import {
  IsBoolean,
  IsEmail,
  IsEnum,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { CustomerType } from '@prisma/client';

export class CreateCustomerDto {
  @ApiProperty({ description: 'Customer contact / entity name' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  name!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  company?: string;

  @ApiPropertyOptional({ description: 'E.164 phone for SMS updates' })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  smsPhone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEmail()
  @MaxLength(200)
  email?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  billingAddress?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  deliveryAddress?: string;

  @ApiPropertyOptional({ enum: CustomerType, default: CustomerType.end_user })
  @IsOptional()
  @IsEnum(CustomerType)
  customerType?: CustomerType;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  smsOptOut?: boolean;

  @ApiPropertyOptional({ description: 'QuickBooks customer reference' })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  qbCustomerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}
