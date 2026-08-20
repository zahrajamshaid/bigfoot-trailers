import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsInt,
  IsISO8601,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  Min,
} from 'class-validator';

export class CreatePayrollAdjustmentDto {
  @ApiProperty({ description: 'Worker the adjustment applies to.' })
  @IsInt()
  @Min(1)
  userId!: number;

  @ApiProperty({
    description: 'Day the adjustment lands on (decides the pay week). YYYY-MM-DD.',
  })
  @IsISO8601({ strict: false })
  effectiveDate!: string;

  @ApiProperty({
    description: 'Dollar amount. Positive = bonus/correction, negative = deduction.',
  })
  @IsNumber()
  dollars!: number;

  @ApiProperty({ description: 'Reason shown on the payroll line.' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  note!: string;
}

export class UpdatePayrollAdjustmentDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  dollars?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  note?: string;
}

export class QueryPayrollAdjustmentsDto {
  @ApiPropertyOptional({ description: 'Sunday week-start (YYYY-MM-DD) to scope to.' })
  @IsOptional()
  @IsISO8601({ strict: false })
  weekStart?: string;

  @ApiPropertyOptional({ description: 'Filter to a single worker.' })
  @IsOptional()
  @IsInt()
  userId?: number;
}
