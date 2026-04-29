import { IsInt, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class SetPriorityDto {
  @ApiProperty({ description: 'Global priority value (lower = higher priority)' })
  @IsInt()
  @Min(1)
  @Type(() => Number)
  globalPriority!: number;
}
