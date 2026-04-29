import { IsNotEmpty, IsNumber, IsString } from 'class-validator';
import { Type } from 'class-transformer';

export class PresignUploadDto {
  @IsString()
  @IsNotEmpty()
  fileType!: string;

  @IsNumber()
  @Type(() => Number)
  trailerId!: number;

  @IsString()
  @IsNotEmpty()
  fileName!: string;
}
