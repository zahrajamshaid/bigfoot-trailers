import { IsOptional, IsArray, IsString } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';

export class CompleteBatchDto {
  @ApiPropertyOptional({
    description:
      'Optional proof-of-delivery photo storage keys — attached to every delivery in the batch',
    type: [String],
  })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  photoStorageKeys?: string[];
}
