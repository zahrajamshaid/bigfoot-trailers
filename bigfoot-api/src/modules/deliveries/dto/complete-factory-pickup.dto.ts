import { IsOptional, IsString, IsNumber, Min, MaxLength } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class CompleteFactoryPickupDto {
  @ApiPropertyOptional({ description: 'Name of the person who picked up the trailer' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  pickedUpByName?: string;

  @ApiPropertyOptional({ description: 'Balance collected at pickup' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Type(() => Number)
  paymentCollected?: number;
}
