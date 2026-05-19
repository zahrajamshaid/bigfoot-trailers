import { IsOptional, IsNumber, IsDateString, Min } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class UpdatePointValueDto {
  @ApiPropertyOptional({ description: 'Updated points value', example: 4.0 })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Type(() => Number)
  points?: number;

  @ApiPropertyOptional({
    description: 'End date for this rate (YYYY-MM-DD)',
    example: '2026-06-30',
  })
  @IsOptional()
  @IsDateString()
  effectiveTo?: string;
}
