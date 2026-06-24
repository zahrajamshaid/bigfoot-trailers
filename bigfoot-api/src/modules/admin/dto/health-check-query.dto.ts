import { IsDateString, IsIn, IsOptional } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export const HEALTH_CHECK_PERIODS = [
  'weekly',
  'biweekly',
  'monthly',
  'custom',
] as const;
export type HealthCheckPeriod = (typeof HEALTH_CHECK_PERIODS)[number];

export class HealthCheckQueryDto {
  @ApiProperty({
    description:
      'Period bucket. weekly = Sun-Sat window containing `start`; biweekly = 14 days from that Sunday; monthly = calendar month containing `start`; custom = explicit [start, end] inclusive.',
    enum: HEALTH_CHECK_PERIODS,
    default: 'weekly',
    required: false,
  })
  @IsOptional()
  @IsIn(HEALTH_CHECK_PERIODS as unknown as string[])
  period?: HealthCheckPeriod;

  @ApiProperty({
    description:
      'YYYY-MM-DD. For weekly/biweekly/monthly this is any date inside the desired window. For custom this is the inclusive start. Defaults to today.',
    example: '2026-06-21',
    required: false,
  })
  @IsOptional()
  @IsDateString()
  start?: string;

  @ApiProperty({
    description:
      'YYYY-MM-DD. Required when period=custom — the inclusive end date of the window.',
    example: '2026-06-30',
    required: false,
  })
  @IsOptional()
  @IsDateString()
  end?: string;
}
