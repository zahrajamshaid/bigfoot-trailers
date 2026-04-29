import { IsBoolean } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class ToggleHotDto {
  @ApiProperty({ description: 'Set is_hot flag on trailer' })
  @IsBoolean()
  isHot!: boolean;
}
