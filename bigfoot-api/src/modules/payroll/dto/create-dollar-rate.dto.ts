import { IsInt, IsNumber, IsDateString, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class CreateDollarRateDto {
  @ApiProperty({ description: 'FK to departments' })
  @IsInt()
  @Type(() => Number)
  departmentId!: number;

  @ApiProperty({ description: 'Dollar amount per point', example: 12.5 })
  @IsNumber({ maxDecimalPlaces: 4 })
  @Min(0)
  @Type(() => Number)
  dollarPerPoint!: number;

  @ApiProperty({ description: 'Date this rate becomes effective (YYYY-MM-DD)', example: '2026-01-01' })
  @IsDateString()
  effectiveFrom!: string;
}
