import { IsString, IsNotEmpty } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class FailDeliveryDto {
  @ApiProperty({ description: 'Reason for delivery failure' })
  @IsString()
  @IsNotEmpty()
  failReason!: string;
}
