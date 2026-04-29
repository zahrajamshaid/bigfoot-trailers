import { IsArray, IsString, IsEnum, ArrayMinSize } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export enum PhotoTypeDto {
  PROOF_OF_DELIVERY = 'proof_of_delivery',
  DAMAGE = 'damage',
}

export class UploadDeliveryPhotosDto {
  @ApiProperty({ description: 'Storage keys of photos', type: [String] })
  @IsArray()
  @IsString({ each: true })
  @ArrayMinSize(1)
  storageKeys!: string[];

  @ApiPropertyOptional({ enum: PhotoTypeDto, default: 'proof_of_delivery' })
  @IsEnum(PhotoTypeDto)
  photoType!: PhotoTypeDto;
}
