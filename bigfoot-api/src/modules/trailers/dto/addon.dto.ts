import { IsString, IsOptional, MaxLength, IsNotEmpty } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class CreateAddonDto {
  @ApiProperty({ description: 'Name of the addon (e.g. winch, tongue box)' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(150)
  addonName!: string;

  @ApiPropertyOptional({ description: 'Optional notes about the addon' })
  @IsOptional()
  @IsString()
  notes?: string;
}
