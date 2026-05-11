import { Controller, Get, Query } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiQuery,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsBoolean, IsOptional } from 'class-validator';
import { LocationsService } from './locations.service';

class QueryLocationsDto {
  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  @IsBoolean()
  stockOnly?: boolean;

  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  @IsBoolean()
  activeOnly?: boolean;
}

@ApiTags('Locations')
@ApiBearerAuth('JWT')
@Controller('locations')
export class LocationsController {
  constructor(private readonly locationsService: LocationsService) {}

  @Get()
  @ApiOperation({
    summary: 'List locations (yards, factory). Use stockOnly=true to exclude factory.',
  })
  @ApiQuery({ name: 'stockOnly', required: false, type: Boolean })
  @ApiQuery({ name: 'activeOnly', required: false, type: Boolean })
  @ApiResponse({ status: 200, description: 'Array of locations' })
  async findAll(@Query() query: QueryLocationsDto) {
    return this.locationsService.findAll({
      stockOnly: query.stockOnly,
      activeOnly: query.activeOnly,
    });
  }
}
