import { IsEnum } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

// Step 9 of every production line is either WIRE or HYDRAULICS (QC_5 inspects
// whichever ran). Auto-routing puts XP / Yeti / Deck-Over on WIRE and the
// gooseneck-line series (gooseneck_dump, gooseneck_yeti, cxp) on HYDRAULICS;
// this enum is the manual override, mirroring the paint-booth swap. Codes match
// the department.code values seeded in seed.ts.
export enum WireHydraulicCode {
  WIRE = 'WIRE',
  HYDRAULICS = 'HYDRAULICS',
}

export class SetWireHydraulicDto {
  @ApiProperty({
    enum: WireHydraulicCode,
    description:
      "Target department. The trailer's WIRE/HYDRAULICS production_step is " +
      'moved to this department (step status/queue position preserved).',
  })
  @IsEnum(WireHydraulicCode)
  departmentCode!: WireHydraulicCode;
}
