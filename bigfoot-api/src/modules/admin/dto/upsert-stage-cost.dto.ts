import { IsDateString, IsInt, IsNumber, IsOptional, Min } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

/**
 * Upsert a single (trailer model, department) cost cell. Mirrors the
 * payroll point-value upsert pattern — supply effectiveFrom to backdate or
 * tag a future change; omit it to mark "as of today".
 */
export class UpsertStageCostDto {
  @ApiProperty({ description: 'FK to trailer_models.id' })
  @IsInt()
  @Type(() => Number)
  trailerModelId!: number;

  @ApiProperty({ description: 'FK to departments.id (non-QC only)' })
  @IsInt()
  @Type(() => Number)
  departmentId!: number;

  @ApiProperty({ description: 'Approx dollar cost for this stage', example: 425.50 })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Type(() => Number)
  costDollars!: number;

  @ApiPropertyOptional({
    description: 'Effective-from date (YYYY-MM-DD). Defaults to today.',
    example: '2026-06-19',
  })
  @IsOptional()
  @IsDateString()
  effectiveFrom?: string;
}
