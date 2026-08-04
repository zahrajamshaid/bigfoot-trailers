import { IsString, MinLength, MaxLength } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class CreateTicketDto {
  @ApiProperty({ example: 'Trailers list keeps crashing', maxLength: 160 })
  @IsString()
  @MinLength(3)
  @MaxLength(160)
  subject!: string;

  @ApiProperty({ example: 'Every time I open the trailers tab the app closes.' })
  @IsString()
  @MinLength(1)
  @MaxLength(4000)
  body!: string;
}

export class CreateMessageDto {
  @ApiProperty({ example: 'Thanks — can you tell me what phone you are on?' })
  @IsString()
  @MinLength(1)
  @MaxLength(4000)
  body!: string;
}
