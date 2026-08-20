import {
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

/** Manual pay add-ons captured at completion for specific departments:
 *  WIRE (hydraulic jack / toolbox), PAINT (ramp jacks), WOOD (tire swaps). */
export class PayAdjustmentsDto {
  @ApiPropertyOptional({ enum: ['single', 'double', 'ramps_jack'] })
  @IsOptional()
  @IsIn(['single', 'double', 'ramps_jack'])
  hydraulicJack?: 'single' | 'double' | 'ramps_jack';

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  toolbox?: boolean;

  @ApiPropertyOptional({ description: 'Ramp jacks painted separately' })
  @IsOptional()
  @IsInt()
  @Min(0)
  rampJacks?: number;

  @ApiPropertyOptional({ description: 'Tire swaps done after build' })
  @IsOptional()
  @IsInt()
  @Min(0)
  tireSwaps?: number;
}

export class StepCheckResultDto {
  @ApiProperty({ description: 'QcChecklistItem.id' })
  @IsInt()
  checklistItemId!: number;

  @ApiProperty({ description: 'Whether the worker confirmed this item' })
  @IsBoolean()
  passed!: boolean;

  @ApiPropertyOptional({
    description: 'Optional note (required/recommended when passed=false)',
  })
  @IsOptional()
  @IsString()
  note?: string;
}

export class CompleteStepDto {
  @ApiPropertyOptional({ description: 'Optional notes for the completion' })
  @IsOptional()
  @IsString()
  notes?: string;

  @ApiPropertyOptional({
    description:
      "Worker self-check results. Required when the step's department has active upstream checklist items.",
    type: [StepCheckResultDto],
  })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => StepCheckResultDto)
  checklistResults?: StepCheckResultDto[];

  @ApiPropertyOptional({ type: PayAdjustmentsDto })
  @IsOptional()
  @ValidateNested()
  @Type(() => PayAdjustmentsDto)
  payAdjustments?: PayAdjustmentsDto;

  @ApiPropertyOptional({
    description:
      'Crew members (userIds) who were absent for this completion. On a crew stage they are skipped from the pay split; each present member still earns their slot rate.',
    type: [Number],
  })
  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  absentCrewUserIds?: number[];
}
