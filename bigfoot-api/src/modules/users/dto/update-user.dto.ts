import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsEmail,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
  Matches,
} from 'class-validator';
import { UserRoleDto } from './create-user.dto';

export class UpdateUserDto {
  @ApiPropertyOptional({ example: 'john.doe@bigfoottrailers.com' })
  @IsOptional()
  @IsEmail()
  email?: string;

  @ApiPropertyOptional({ example: 'John Doe' })
  @IsOptional()
  @IsString()
  @MaxLength(150)
  fullName?: string;

  @ApiPropertyOptional({ example: '+1234567890' })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  @Matches(/^\+?[\d\s\-()]+$/, { message: 'phone must be a valid phone number format' })
  phone?: string;

  @ApiPropertyOptional({ example: 'NewSecurePass123!', minLength: 8 })
  @IsOptional()
  @IsString()
  @MinLength(8)
  @MaxLength(128)
  password?: string;

  /** Only owner can change roles. */
  @ApiPropertyOptional({ enum: UserRoleDto, example: 'worker' })
  @IsOptional()
  @IsEnum(UserRoleDto)
  role?: UserRoleDto;

  @ApiPropertyOptional({ description: 'FK to departments.id', example: 1 })
  @IsOptional()
  @IsInt()
  primaryDepartmentId?: number | null;

  @ApiPropertyOptional({ description: 'FK to locations.id', example: 1 })
  @IsOptional()
  @IsInt()
  primaryLocationId?: number | null;
}
