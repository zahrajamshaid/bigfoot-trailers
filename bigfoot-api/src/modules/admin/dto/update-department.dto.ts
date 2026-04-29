import { IsInt, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class UpdateDepartmentDto {
  @ApiProperty({ description: 'Hours before a stall alert fires', example: 48 })
  @IsInt()
  @Min(1)
  stallThresholdHours!: number;
}
