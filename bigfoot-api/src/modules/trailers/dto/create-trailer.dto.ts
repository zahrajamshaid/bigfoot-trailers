import {
  IsString,
  IsInt,
  IsOptional,
  IsBoolean,
  MaxLength,
  IsNotEmpty,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class CreateTrailerDto {
  @ApiProperty({ description: 'Unique Sales Order number from QuickBooks' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(30)
  soNumber!: string;

  @ApiProperty({ description: 'FK to trailer_models — determines workflow series' })
  @IsInt()
  @Type(() => Number)
  trailerModelId!: number;

  @ApiPropertyOptional({ description: 'Paint color' })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  color?: string;

  @ApiPropertyOptional({ description: 'Physical size (e.g. "16ft")' })
  @IsOptional()
  @IsString()
  @MaxLength(10)
  sizeFt?: string;

  @ApiPropertyOptional({ description: 'Special instructions / add-on notes' })
  @IsOptional()
  @IsString()
  optionsNotes?: string;

  @ApiPropertyOptional({ description: 'Short free-form note (max 500 chars)' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  specialNote?: string;

  @ApiPropertyOptional({ description: 'FK to customers. Nullable for stock builds.' })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  customerId?: number;

  @ApiPropertyOptional({
    description:
      'Free-text customer / buyer name. A trailer with a name is treated ' +
      'as sold. Preferred over customerId — customer records move to the ' +
      'GoHighLevel integration.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  soldToName?: string;

  @ApiPropertyOptional({ description: 'True if building for inventory', default: false })
  @IsOptional()
  @IsBoolean()
  isStockBuild?: boolean;

  @ApiPropertyOptional({
    description: 'Destination stock location ID when isStockBuild=true',
  })
  @IsOptional()
  @IsInt()
  @Type(() => Number)
  stockLocationId?: number;

  @ApiPropertyOptional({ description: 'QuickBooks SO object ID for future sync' })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  qbSoId?: string;
}
