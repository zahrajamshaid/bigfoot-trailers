import {
  Controller,
  Get,
  Post,
  Patch,
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
import { QcService } from './qc.service';
import {
  CreateChecklistItemDto,
  UpdateChecklistItemDto,
  QueryChecklistItemsDto,
  SubmitInspectionDto,
} from './dto';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';

@ApiTags('Quality Control')
@ApiBearerAuth('JWT')
@Controller('qc')
export class QcController {
  constructor(private readonly qcService: QcService) {}

  // ---------------------------------------------------------------------------
  // GET /qc/stats — dashboard summary
  // ---------------------------------------------------------------------------
  @Get('stats')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER, UserRole.QC_INSPECTOR)
  @ApiOperation({ summary: 'QC dashboard summary (ready, today, rework)' })
  @ApiResponse({ status: 200, description: 'QC stats' })
  async getQcStats() {
    return this.qcService.getQcStats();
  }

  // ---------------------------------------------------------------------------
  // GET /qc/rework-queue — drilldown behind the dashboard rework tile
  // ---------------------------------------------------------------------------
  @Get('rework-queue')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER, UserRole.QC_INSPECTOR)
  @ApiOperation({
    summary: 'Trailers currently in rework (production_steps active+isRework)',
    description:
      'Returns the active production_steps with isRework=true — i.e. ' +
      'trailers QC sent back to an earlier department that the worker ' +
      'has not finished redoing yet.',
  })
  @ApiResponse({ status: 200, description: 'List of in-flight rework steps' })
  async getReworkQueue() {
    return this.qcService.getReworkQueue();
  }

  // ---------------------------------------------------------------------------
  // GET /qc/failed-inspections — drilldown list behind the fail-rate stat
  // ---------------------------------------------------------------------------
  @Get('failed-inspections')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER, UserRole.QC_INSPECTOR)
  @ApiOperation({
    summary: 'Recent failed QC inspections (with trailer + dept context)',
    description:
      'Backs the dashboard fail-rate tap. Returns failed QcInspection rows ' +
      'over a rolling window — default 30 days. Newest first.',
  })
  @ApiResponse({ status: 200, description: 'List of failed inspections' })
  async getFailedInspections(@Query('days') daysParam?: string) {
    const days = Math.max(1, Math.min(180, Number(daysParam) || 30));
    return this.qcService.getFailedInspections(days);
  }

  // ---------------------------------------------------------------------------
  // GET /qc/checklist-items
  // ---------------------------------------------------------------------------
  @Get('checklist-items')
  @ApiOperation({ summary: 'List QC checklist template items with optional filters' })
  @ApiResponse({ status: 200, description: 'List of checklist items' })
  async findChecklistItems(@Query() query: QueryChecklistItemsDto) {
    return this.qcService.findChecklistItems(query);
  }

  // ---------------------------------------------------------------------------
  // POST /qc/checklist-items — production_manager, owner
  // ---------------------------------------------------------------------------
  @Post('checklist-items')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a QC checklist item' })
  @ApiResponse({ status: 201, description: 'Checklist item created' })
  @ApiResponse({ status: 400, description: 'Department is not a QC department' })
  async createChecklistItem(@Body() dto: CreateChecklistItemDto) {
    return this.qcService.createChecklistItem(dto);
  }

  // ---------------------------------------------------------------------------
  // PATCH /qc/checklist-items/:id — production_manager, owner
  // ---------------------------------------------------------------------------
  @Patch('checklist-items/:id')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Update or deactivate a QC checklist item' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Checklist item updated' })
  @ApiResponse({ status: 404, description: 'Checklist item not found' })
  async updateChecklistItem(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateChecklistItemDto,
  ) {
    return this.qcService.updateChecklistItem(id, dto);
  }

  // ---------------------------------------------------------------------------
  // POST /qc/inspections — qc_inspector, production_manager, owner
  // ---------------------------------------------------------------------------
  @Post('inspections')
  @Roles(UserRole.QC_INSPECTOR, UserRole.PRODUCTION_MANAGER, UserRole.OWNER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Submit a QC inspection (pass or fail)' })
  @ApiResponse({ status: 200, description: 'Inspection submitted' })
  @ApiResponse({ status: 400, description: 'Validation error or invalid rework target' })
  @ApiResponse({ status: 404, description: 'Step not found' })
  async submitInspection(
    @Body() dto: SubmitInspectionDto,
    @CurrentUser() requester: JwtPayload,
  ) {
    return this.qcService.submitInspection(dto, BigInt(requester.sub));
  }

  // ---------------------------------------------------------------------------
  // GET /qc/inspections/:id
  // ---------------------------------------------------------------------------
  @Get('inspections/:id')
  @ApiOperation({
    summary: 'Get a single QC inspection with checklist results and photos',
  })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Inspection detail' })
  @ApiResponse({ status: 404, description: 'Inspection not found' })
  async findInspection(@Param('id', ParseIntPipe) id: number) {
    return this.qcService.findInspection(BigInt(id));
  }

  // ---------------------------------------------------------------------------
  // POST /qc/inspections/:id/send-customer-sms — qc_inspector, production_manager
  // ---------------------------------------------------------------------------
  @Post('inspections/:id/send-customer-sms')
  @Roles(UserRole.QC_INSPECTOR, UserRole.PRODUCTION_MANAGER, UserRole.OWNER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Dispatch trailer_complete SMS for a FINAL_QC pass' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'SMS dispatched' })
  @ApiResponse({ status: 400, description: 'Not a FINAL_QC pass or already sent' })
  @ApiResponse({ status: 404, description: 'Inspection or queued SMS not found' })
  async sendCustomerSms(@Param('id', ParseIntPipe) id: number) {
    return this.qcService.sendCustomerSms(BigInt(id));
  }

  // ---------------------------------------------------------------------------
  // GET /qc/inspections/step/:step_id
  // ---------------------------------------------------------------------------
  @Get('inspections/step/:step_id')
  @ApiOperation({ summary: 'Get all inspections for a given production step' })
  @ApiParam({ name: 'step_id', type: 'number' })
  @ApiResponse({ status: 200, description: 'List of inspections for the step' })
  @ApiResponse({ status: 404, description: 'Step not found' })
  async findInspectionsByStep(@Param('step_id', ParseIntPipe) stepId: number) {
    return this.qcService.findInspectionsByStep(BigInt(stepId));
  }
}
