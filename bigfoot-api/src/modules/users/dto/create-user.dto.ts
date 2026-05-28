import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsEmail,
  IsEnum,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
  Matches,
} from 'class-validator';

/**
 * Matches the Prisma UserRole enum and user_role_enum in PostgreSQL.
 * Duplicated from @common/decorators/roles.decorator for DTO validation
 * since DTOs should not depend on guard internals.
 */
export enum UserRoleDto {
  OWNER = 'owner',
  PRODUCTION_MANAGER = 'production_manager',
  TRANSPORT_MANAGER = 'transport_manager',
  QC_INSPECTOR = 'qc_inspector',
  WORKER = 'worker',
  SALES = 'sales',
  DRIVER = 'driver',
  OFFICE = 'office',
  PURCHASING = 'purchasing',
}

export class CreateUserDto {
  @ApiProperty({ example: 'john.doe@bigfoottrailers.com' })
  @IsEmail()
  @IsNotEmpty()
  email!: string;

  @ApiProperty({ example: 'John Doe' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(150)
  fullName!: string;

  @ApiProperty({ example: 'SecurePass123!', minLength: 8 })
  @IsString()
  @IsNotEmpty()
  @MinLength(8)
  @MaxLength(128)
  password!: string;

  @ApiPropertyOptional({ example: '+1234567890' })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  @Matches(/^\+?[\d\s\-()]+$/, { message: 'phone must be a valid phone number format' })
  phone?: string;

  @ApiProperty({ enum: UserRoleDto, example: 'worker' })
  @IsEnum(UserRoleDto)
  role!: UserRoleDto;

  @ApiPropertyOptional({ description: 'FK to departments.id', example: 1 })
  @IsOptional()
  @IsInt()
  primaryDepartmentId?: number;

  @ApiPropertyOptional({ description: 'FK to locations.id', example: 1 })
  @IsOptional()
  @IsInt()
  primaryLocationId?: number;
}
