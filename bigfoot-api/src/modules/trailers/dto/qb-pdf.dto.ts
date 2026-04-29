import { IsString, IsNotEmpty, MaxLength } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class UploadQbPdfDto {
  @ApiProperty({ description: 'DigitalOcean Spaces storage key for the QB SO PDF' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(300)
  storageKey!: string;

  @ApiProperty({ description: 'Pre-signed or public URL for the uploaded PDF' })
  @IsString()
  @IsNotEmpty()
  storageUrl!: string;
}
