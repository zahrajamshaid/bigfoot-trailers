import { IsNotEmpty, IsNumber, IsString } from 'class-validator';
import { Type } from 'class-transformer';

export class CreateWorkerMessageDto {
  @IsNumber()
  @Type(() => Number)
  trailerId!: number;

  @IsNumber()
  @Type(() => Number)
  toUserId!: number;

  @IsString()
  @IsNotEmpty()
  messageText!: string;
}
