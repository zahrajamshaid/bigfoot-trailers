import {
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  IsBoolean,
  IsArray,
  ValidateNested,
  MaxLength,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export enum QcResultDto {
  PASS = 'pass',
  FAIL = 'fail',
}

export class ChecklistResultEntryDto {
  @ApiProperty({ description: 'FK to qc_checklist_items' })
  @IsInt()
  @Type(() => Number)
  checklistItemId!: number;

  @ApiProperty({ description: 'Whether this item passed' })
  @IsBoolean()
  passed!: boolean;

  @ApiPropertyOptional({ description: 'Optional note for this checklist item' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

export class SubmitInspectionDto {
  @ApiProperty({ description: 'The active QC production step being inspected' })
  @IsInt()
  @Type(() => Number)
  productionStepId!: number;

  @ApiProperty({ description: 'Inspection result: pass or fail', enum: QcResultDto })
  @IsEnum(QcResultDto)
  result!: QcResultDto;

  @ApiPropertyOptional({ description: 'Required when result=fail. Describes the defect.' })
  @IsOptional()
  @IsString()
  failNotes?: string;

  @ApiPropertyOptional({ description: 'Required when result=fail. Target department for rework.' })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  reworkTargetDepartmentId?: number;

  @ApiProperty({ description: 'Array of checklist results — one per active checklist item', type: [ChecklistResultEntryDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => ChecklistResultEntryDto)
  checklistResults!: ChecklistResultEntryDto[];

  @ApiProperty({ description: 'DO Spaces storage keys of photos.' })
  @IsArray()
  @IsString({ each: true })
  photoStorageKeys!: string[];
}
