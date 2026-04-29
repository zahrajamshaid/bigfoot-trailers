import { IsDateString } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class WeeklyReportQueryDto {
  @ApiProperty({ description: 'Week start date (must be a Sunday)', example: '2026-03-22' })
  @IsDateString()
  weekStart!: string;
}
