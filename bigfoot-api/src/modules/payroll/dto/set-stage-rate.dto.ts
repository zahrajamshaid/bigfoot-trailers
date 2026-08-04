import { IsInt, IsNumber, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class SetStageRateDto {
  @ApiProperty()
  @IsInt()
  trailerModelId!: number;

  @ApiProperty()
  @IsInt()
  departmentId!: number;

  @ApiProperty({ description: 'Flat worker pay ($) for this stage' })
  @IsNumber()
  @Min(0)
  pay!: number;
}
