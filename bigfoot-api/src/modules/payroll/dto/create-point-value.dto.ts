import { IsInt, IsNumber, IsDateString, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class CreatePointValueDto {
  @ApiProperty({ description: 'FK to trailer_models' })
  @IsInt()
  @Type(() => Number)
  trailerModelId!: number;

  @ApiProperty({
    description: 'FK to departments — must be a production (non-QC) department',
  })
  @IsInt()
  @Type(() => Number)
  departmentId!: number;

  @ApiProperty({
    description: 'Points awarded for completing this model in this department',
    example: 3.5,
  })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Type(() => Number)
  points!: number;

  @ApiProperty({
    description: 'Date this rate becomes effective (YYYY-MM-DD)',
    example: '2026-01-01',
  })
  @IsDateString()
  effectiveFrom!: string;
}
