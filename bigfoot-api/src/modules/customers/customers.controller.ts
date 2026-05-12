import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiParam,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { CustomersService } from './customers.service';
import {
  CreateCustomerDto,
  UpdateCustomerDto,
  QueryCustomersDto,
} from './dto';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';

@ApiTags('Customers')
@ApiBearerAuth('JWT')
@Controller('customers')
export class CustomersController {
  constructor(private readonly customersService: CustomersService) {}

  @Get()
  @Roles(
    UserRole.OWNER,
    UserRole.SALES,
    UserRole.OFFICE,
    UserRole.PRODUCTION_MANAGER,
    UserRole.TRANSPORT_MANAGER,
  )
  @ApiOperation({ summary: 'List customers with search + pagination' })
  @ApiResponse({ status: 200, description: 'Paginated customers envelope' })
  async findAll(@Query() query: QueryCustomersDto) {
    return this.customersService.findAll(query);
  }

  @Get(':id')
  @Roles(
    UserRole.OWNER,
    UserRole.SALES,
    UserRole.OFFICE,
    UserRole.PRODUCTION_MANAGER,
    UserRole.TRANSPORT_MANAGER,
  )
  @ApiOperation({ summary: 'Get customer detail with recent trailers' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Customer detail' })
  @ApiResponse({ status: 404, description: 'Customer not found' })
  async findOne(@Param('id', ParseIntPipe) id: number) {
    return this.customersService.findOne(BigInt(id));
  }

  @Post()
  @Roles(UserRole.OWNER, UserRole.SALES, UserRole.OFFICE)
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a customer' })
  @ApiResponse({ status: 201, description: 'Customer created' })
  async create(@Body() dto: CreateCustomerDto) {
    return this.customersService.create(dto);
  }

  @Patch(':id')
  @Roles(UserRole.OWNER, UserRole.SALES, UserRole.OFFICE)
  @ApiOperation({ summary: 'Update a customer' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Customer updated' })
  @ApiResponse({ status: 404, description: 'Customer not found' })
  async update(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateCustomerDto,
  ) {
    return this.customersService.update(BigInt(id), dto);
  }

  @Delete(':id')
  @Roles(UserRole.OWNER)
  @ApiOperation({
    summary:
      'Delete customer. Fails with 400 if trailers reference this customer ' +
      'unless cascadeTrailers=true, in which case ALL referencing trailers ' +
      '(and their production steps, QC inspections, photos, deliveries, ' +
      'messages, stall alerts, push notifications, SMS logs, and location ' +
      'receipts) are deleted in the same atomic transaction.',
  })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Customer deleted' })
  @ApiResponse({ status: 400, description: 'Customer has referencing trailers (and cascadeTrailers not set)' })
  @ApiResponse({ status: 404, description: 'Customer not found' })
  async remove(
    @Param('id', ParseIntPipe) id: number,
    @Query('cascadeTrailers') cascadeTrailers?: string,
  ) {
    const cascade = cascadeTrailers === 'true' || cascadeTrailers === '1';
    return this.customersService.remove(BigInt(id), { cascadeTrailers: cascade });
  }
}
