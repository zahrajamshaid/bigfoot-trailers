import {
  IsArray,
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

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
}
