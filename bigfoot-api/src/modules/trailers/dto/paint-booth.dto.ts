import { IsEnum } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

// The two paint booths the manager can swap between. Codes mirror the
// department.code values seeded in seed.ts.
export enum PaintBoothCode {
  PAINT_A = 'PAINT_A',
  PAINT_B = 'PAINT_B',
}

export class SetPaintBoothDto {
  @ApiProperty({
    enum: PaintBoothCode,
    description:
      'Target paint booth. The trailer\'s paint production_step is moved to ' +
      'this booth (step status/queue position preserved).',
  })
  @IsEnum(PaintBoothCode)
  paintBoothCode!: PaintBoothCode;
}
