import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsArray, IsInt, IsOptional, IsString, MaxLength } from 'class-validator';

/**
 * Admin override that places a trailer at a specific production step.
 *
 * Steps before the target are forced to `complete` (with no points and the
 * admin recorded as completer for any that weren't already complete). The
 * target step becomes `active`. Steps after the target are reset to `waiting`
 * — their previous completion data is wiped and a `step_reversals` row is
 * recorded for each so the rollback shows up in the audit history.
 */
export class JumpToStepDto {
  @ApiProperty({ description: 'Target production step id (must belong to the trailer)' })
  @IsInt()
  @Type(() => Number)
  stepId!: number;

  @ApiPropertyOptional({
    description: 'Optional reason recorded on every rollback row + audit log',
  })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;

  @ApiPropertyOptional({
    description:
      'Bypassed (upstream) step ids the PM confirms were actually worked. Their crews are paid as the jump force-completes them (crew stages only).',
    type: [Number],
  })
  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  payStepIds?: number[];
}
