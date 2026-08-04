import { IsArray, IsInt, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class SetStageCrewDto {
  @ApiProperty({
    description:
      'Ordered worker user IDs — slot 0 first. Slot i earns the model worker_split[i]. Empty clears the roster.',
    type: [Number],
  })
  @IsArray()
  @IsInt({ each: true })
  @Min(1, { each: true })
  userIds!: number[];
}
