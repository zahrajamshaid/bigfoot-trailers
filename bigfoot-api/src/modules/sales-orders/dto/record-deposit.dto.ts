import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsISO8601,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MaxLength,
} from 'class-validator';

/** Record an initial deposit received on a trailer (posts a QBO Payment). */
export class RecordDepositDto {
  @ApiProperty({ description: 'Deposit amount received (must be > 0)' })
  @IsNumber({ maxDecimalPlaces: 2 })
  @IsPositive()
  amount!: number;

  @ApiPropertyOptional({ description: 'How it was paid (cash, card, check, …)' })
  @IsOptional()
  @IsString()
  @MaxLength(40)
  method?: string;

  @ApiPropertyOptional({
    description: 'Date received (yyyy-mm-dd). Defaults to today.',
  })
  @IsOptional()
  @IsISO8601()
  paidAt?: string;
}
