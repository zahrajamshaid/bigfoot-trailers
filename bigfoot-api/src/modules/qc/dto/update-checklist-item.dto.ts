import { IsString, IsOptional, IsBoolean, IsInt, MaxLength, Min } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class UpdateChecklistItemDto {
  @ApiPropertyOptional({ description: 'Updated label text' })
  @IsOptional()
  @IsString()
  @MaxLength(300)
  itemLabel?: string;

  @ApiPropertyOptional({ description: 'Updated sort order' })
  @IsOptional()
  @IsInt()
  @Min(0)
  @Type(() => Number)
  sortOrder?: number;

  @ApiPropertyOptional({ description: 'Deactivate this checklist item' })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
