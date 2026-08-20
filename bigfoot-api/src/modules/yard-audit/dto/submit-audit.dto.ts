import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsArray,
  IsInt,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

/// One trailer physically found in the yard that the app did NOT list there
/// (wrong-yard or unknown). Either an SO number, a free-text note, or both.
export class AuditExtraDto {
  @ApiPropertyOptional({ description: 'SO number read off the trailer, if legible.' })
  @IsOptional()
  @IsString()
  @MaxLength(30)
  soNumber?: string;

  @ApiPropertyOptional({
    description: 'Free-text note (e.g. model, colour, where it sat).',
  })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

export class SubmitAuditDto {
  @ApiProperty({ description: 'The yard/location being audited.' })
  @IsInt()
  @Min(1)
  locationId!: number;

  @ApiPropertyOptional({
    description:
      'Trailer ids the app lists at this yard but that were NOT physically found. One problem report is opened per trailer.',
    type: [Number],
  })
  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  missingTrailerIds?: number[];

  @ApiPropertyOptional({
    description:
      'Trailers physically present at the yard that the app did not expect there. One problem report is opened per entry.',
    type: [AuditExtraDto],
  })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => AuditExtraDto)
  extras?: AuditExtraDto[];
}
