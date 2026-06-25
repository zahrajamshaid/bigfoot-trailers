import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  HttpCode,
  HttpStatus,
  ParseIntPipe,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiParam,
} from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { PayrollService } from './payroll.service';
import {
  CreatePointValueDto,
  UpdatePointValueDto,
  QueryPointValuesDto,
  CreateDollarRateDto,
  QueryDollarRatesDto,
  QueryPayrollRecordsDto,
} from './dto';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';

@ApiTags('Payroll')
@ApiBearerAuth('JWT')
@Controller('payroll')
// Payroll data is sensitive; tighten from 100/min global to 30/min per IP
@Throttle({ default: { ttl: 60_000, limit: 30 } })
export class PayrollController {
  constructor(private readonly payrollService: PayrollService) {}

  // ---------------------------------------------------------------------------
  // GET /payroll/point-values
  // ---------------------------------------------------------------------------
  @Get('point-values')
  @ApiOperation({ summary: 'List point values matrix (trailer_model x department)' })
  @ApiResponse({ status: 200, description: 'List of point values' })
  async findPointValues(@Query() query: QueryPointValuesDto) {
    return this.payrollService.findPointValues(query);
  }

  // ---------------------------------------------------------------------------
  // POST /payroll/point-values — owner + production_manager
  // ---------------------------------------------------------------------------
  @Post('point-values')
  // Payroll is full-admin + production_manager — Office is now full admin
  // and gets the same payroll access as owner. QC is excluded (financial).
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.PRODUCTION_MANAGER)
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a point value entry' })
  @ApiResponse({ status: 201, description: 'Point value created' })
  @ApiResponse({ status: 400, description: 'Invalid department or trailer model' })
  async createPointValue(@Body() dto: CreatePointValueDto) {
    return this.payrollService.createPointValue(dto);
  }

  // ---------------------------------------------------------------------------
  // PATCH /payroll/point-values/:id — owner, production_manager
  // ---------------------------------------------------------------------------
  @Patch('point-values/:id')
  // Payroll is full-admin + production_manager — Office is now full admin
  // and gets the same payroll access as owner. QC is excluded (financial).
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Update a point value entry' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Point value updated' })
  @ApiResponse({ status: 404, description: 'Point value not found' })
  async updatePointValue(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdatePointValueDto,
  ) {
    return this.payrollService.updatePointValue(id, dto);
  }

  // ---------------------------------------------------------------------------
  // GET /payroll/dollar-rates
  // ---------------------------------------------------------------------------
  @Get('dollar-rates')
  @ApiOperation({ summary: 'List department dollar-per-point rates' })
  @ApiResponse({ status: 200, description: 'List of dollar rates' })
  async findDollarRates(@Query() query: QueryDollarRatesDto) {
    return this.payrollService.findDollarRates(query);
  }

  // ---------------------------------------------------------------------------
  // POST /payroll/dollar-rates — owner + production_manager
  // ---------------------------------------------------------------------------
  @Post('dollar-rates')
  // Payroll is full-admin + production_manager — Office is now full admin
  // and gets the same payroll access as owner. QC is excluded (financial).
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.PRODUCTION_MANAGER)
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a dollar-per-point rate entry' })
  @ApiResponse({ status: 201, description: 'Dollar rate created' })
  @ApiResponse({ status: 400, description: 'Invalid department' })
  async createDollarRate(@Body() dto: CreateDollarRateDto) {
    return this.payrollService.createDollarRate(dto);
  }

  // ---------------------------------------------------------------------------
  // DELETE /payroll/dollar-rates/:id — owner + production_manager
  // ---------------------------------------------------------------------------
  @Delete('dollar-rates/:id')
  // Payroll is full-admin + production_manager — Office is now full admin
  // and gets the same payroll access as owner. QC is excluded (financial).
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.PRODUCTION_MANAGER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Delete a dollar-per-point rate entry' })
  @ApiParam({ name: 'id', type: 'number', description: 'Dollar rate id' })
  @ApiResponse({ status: 200, description: 'Dollar rate deleted' })
  @ApiResponse({ status: 404, description: 'Dollar rate not found' })
  async deleteDollarRate(@Param('id', ParseIntPipe) id: number) {
    return this.payrollService.deleteDollarRate(id);
  }

  // ---------------------------------------------------------------------------
  // GET /payroll/records
  // ---------------------------------------------------------------------------
  @Get('records')
  // Payroll is full-admin + production_manager — Office is now full admin
  // and gets the same payroll access as owner. QC is excluded (financial).
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Get payroll records with filters' })
  @ApiResponse({ status: 200, description: 'List of payroll records' })
  async findPayrollRecords(@Query() query: QueryPayrollRecordsDto) {
    return this.payrollService.findPayrollRecords(query);
  }

  // ---------------------------------------------------------------------------
  // GET /payroll/records/week/:week_start
  // ---------------------------------------------------------------------------
  @Get('records/week/:week_start')
  // Payroll is full-admin + production_manager — Office is now full admin
  // and gets the same payroll access as owner. QC is excluded (financial).
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Full weekly payroll report for a specific Sunday' })
  @ApiParam({
    name: 'week_start',
    type: 'string',
    description: 'YYYY-MM-DD (must be a Sunday)',
  })
  @ApiResponse({ status: 200, description: 'Weekly payroll report' })
  @ApiResponse({ status: 400, description: 'INVALID_WEEK_START' })
  async findWeeklyReport(@Param('week_start') weekStart: string) {
    return this.payrollService.findWeeklyReport(weekStart);
  }

  // ---------------------------------------------------------------------------
  // POST /payroll/records/lock/:week_start — owner + production_manager
  // ---------------------------------------------------------------------------
  @Post('records/lock/:week_start')
  // Payroll is full-admin + production_manager — Office is now full admin
  // and gets the same payroll access as owner. QC is excluded (financial).
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.PRODUCTION_MANAGER)
  @Throttle({ default: { ttl: 60_000, limit: 5 } })
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: "Lock a week's payroll" })
  @ApiParam({
    name: 'week_start',
    type: 'string',
    description: 'YYYY-MM-DD (must be a Sunday)',
  })
  @ApiResponse({ status: 200, description: 'Payroll week locked' })
  @ApiResponse({ status: 400, description: 'INVALID_WEEK_START or PAYROLL_WEEK_LOCKED' })
  async lockWeek(
    @Param('week_start') weekStart: string,
    @CurrentUser() requester: JwtPayload,
  ) {
    return this.payrollService.lockWeek(weekStart, BigInt(requester.sub));
  }

  // ---------------------------------------------------------------------------
  // GET /payroll/worker/:user_id/summary
  // ---------------------------------------------------------------------------
  @Get('worker/:user_id/summary')
  @ApiOperation({ summary: 'Real-time current week summary for a worker' })
  @ApiParam({ name: 'user_id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Worker weekly summary' })
  @ApiResponse({ status: 404, description: 'User not found' })
  async getWorkerSummary(@Param('user_id', ParseIntPipe) userId: number) {
    return this.payrollService.getWorkerSummary(BigInt(userId));
  }
}
