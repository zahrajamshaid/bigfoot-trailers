import { IsArray, IsInt } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class ReorderQueueDto {
  @ApiProperty({ description: 'Step IDs in desired queue order', type: [Number] })
  @IsArray()
  @IsInt({ each: true })
  stepIds!: number[];
}
