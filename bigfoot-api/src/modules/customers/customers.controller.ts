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
import { CreateCustomerDto, UpdateCustomerDto, QueryCustomersDto } from './dto';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';

@ApiTags('Customers')
@ApiBearerAuth('JWT')
@Controller('customers')
export class CustomersController {
  constructor(private readonly customersService: CustomersService) {}

  @Get()
  // Customers (and their contact details) are commercial data — owner, office
  // and sales only. Production/transport managers run the floor and the yard;
  // they don't need the customer book, so they no longer see it.
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'List customers with search + pagination' })
  @ApiResponse({ status: 200, description: 'Paginated customers envelope' })
  async findAll(@Query() query: QueryCustomersDto) {
    return this.customersService.findAll(query);
  }

  @Get(':id')
  // Customers (and their contact details) are commercial data — owner, office
  // and sales only. Production/transport managers run the floor and the yard;
  // they don't need the customer book, so they no longer see it.
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
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
  @ApiOperation({ summary: 'Create a customer (syncs to QuickBooks)' })
  @ApiResponse({ status: 201, description: 'Customer created' })
  async create(@Body() dto: CreateCustomerDto) {
    return this.customersService.create(dto);
  }

  @Post('import-from-qbo')
  @Roles(UserRole.OWNER, UserRole.OFFICE)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Import every QuickBooks customer into the app (QBO → app)' })
  @ApiResponse({ status: 200, description: 'Import summary (created/updated)' })
  async importFromQbo() {
    return this.customersService.importFromQbo();
  }

  @Post('export-to-qbo')
  @Roles(UserRole.OWNER, UserRole.OFFICE)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Push every app customer not yet in QuickBooks (app → QBO)' })
  @ApiResponse({ status: 200, description: 'Export summary (exported/failed)' })
  async exportToQbo() {
    return this.customersService.exportToQbo();
  }

  @Post('sync')
  @Roles(UserRole.OWNER, UserRole.OFFICE)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Two-way customer sync with QuickBooks (import then export)' })
  @ApiResponse({ status: 200, description: 'Combined { imported, exported } summary' })
  async sync() {
    return this.customersService.syncAll();
  }

  @Patch(':id')
  @Roles(UserRole.OWNER, UserRole.SALES, UserRole.OFFICE)
  @ApiOperation({ summary: 'Update a customer' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Customer updated' })
  @ApiResponse({ status: 404, description: 'Customer not found' })
  async update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateCustomerDto) {
    return this.customersService.update(BigInt(id), dto);
  }

  @Delete(':id')
  // Customer delete (with cascade) is full-admin — Office now has it.
  @Roles(UserRole.OWNER, UserRole.OFFICE)
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
  @ApiResponse({
    status: 400,
    description: 'Customer has referencing trailers (and cascadeTrailers not set)',
  })
  @ApiResponse({ status: 404, description: 'Customer not found' })
  async remove(
    @Param('id', ParseIntPipe) id: number,
    @Query('cascadeTrailers') cascadeTrailers?: string,
  ) {
    const cascade = cascadeTrailers === 'true' || cascadeTrailers === '1';
    return this.customersService.remove(BigInt(id), { cascadeTrailers: cascade });
  }
}
