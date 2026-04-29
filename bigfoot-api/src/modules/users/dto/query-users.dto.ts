import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsEnum, IsInt, IsOptional, Max, Min } from 'class-validator';
import { Type } from 'class-transformer';
import { UserRoleDto } from './create-user.dto';

export class QueryUsersDto {
  @ApiPropertyOptional({ default: 1, minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({ default: 25, minimum: 1, maximum: 100 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 25;

  @ApiPropertyOptional({ enum: UserRoleDto, description: 'Filter by role' })
  @IsOptional()
  @IsEnum(UserRoleDto)
  role?: UserRoleDto;

  @ApiPropertyOptional({ description: 'Filter by active status', default: true })
  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  isActive?: boolean;

  @ApiPropertyOptional({ description: 'Filter by department ID' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  departmentId?: number;
}
