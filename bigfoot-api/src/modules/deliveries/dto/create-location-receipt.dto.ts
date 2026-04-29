import { IsInt, IsOptional, IsString } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class CreateLocationReceiptDto {
  @ApiProperty({ description: 'FK to deliveries' })
  @IsInt()
  @Type(() => Number)
  deliveryId!: number;

  @ApiProperty({ description: 'FK to trailers' })
  @IsInt()
  @Type(() => Number)
  trailerId!: number;

  @ApiPropertyOptional({ description: 'Notes on receipt condition' })
  @IsOptional()
  @IsString()
  notes?: string;
}
