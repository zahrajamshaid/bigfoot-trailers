import {
  Controller,
  Get,
  Patch,
  Post,
  Body,
  Param,
  Query,
  ParseIntPipe,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiParam,
} from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { AdminService } from './admin.service';
import { AuditLogService } from './audit-log.service';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';
import { QueryAuditLogDto, UpdateDepartmentDto, WeeklyReportQueryDto } from './dto';
import { Request } from 'express';
import { Req } from '@nestjs/common';

@ApiTags('Admin')
@ApiBearerAuth('JWT')
@Controller('admin')
// Tighten from global 100/min to 30/min for admin reads (audit log is heavy)
@Throttle({ default: { ttl: 60_000, limit: 30 } })
export class AdminController {
  constructor(
    private readonly adminService: AdminService,
    private readonly auditLogService: AuditLogService,
  ) {}

  // ---------------------------------------------------------------------------
  // GET /admin/workflow-templates
  // ---------------------------------------------------------------------------
  @Get('workflow-templates')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'List all workflow templates by series' })
  @ApiResponse({ status: 200, description: 'Workflow templates grouped by series' })
  async getWorkflowTemplates() {
    return this.adminService.getWorkflowTemplates();
  }

  // ---------------------------------------------------------------------------
  // GET /admin/trailer-models
  // ---------------------------------------------------------------------------
  @Get('trailer-models')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER, UserRole.SALES, UserRole.OFFICE)
  @ApiOperation({ summary: 'List all trailer models (id, code, display name, series)' })
  @ApiResponse({ status: 200, description: 'Trailer models' })
  async getTrailerModels() {
    return this.adminService.getTrailerModels();
  }

  // ---------------------------------------------------------------------------
  // GET /admin/departments
  // ---------------------------------------------------------------------------
  @Get('departments')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'List all departments' })
  @ApiResponse({ status: 200, description: 'All departments with config' })
  async getDepartments() {
    return this.adminService.getDepartments();
  }

  // ---------------------------------------------------------------------------
  // PATCH /admin/departments/:id
  // ---------------------------------------------------------------------------
  @Patch('departments/:id')
  @Roles(UserRole.OWNER)
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  @ApiOperation({ summary: 'Update department stall threshold' })
  @ApiParam({ name: 'id', type: Number })
  @ApiResponse({ status: 200, description: 'Updated department' })
  async updateDepartment(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateDepartmentDto,
    @CurrentUser() user: JwtPayload,
    @Req() req: Request,
  ) {
    return this.adminService.updateDepartment(
      id,
      dto.stallThresholdHours,
      user.sub,
      req.ip,
    );
  }

  // ---------------------------------------------------------------------------
  // GET /admin/audit-log
  // ---------------------------------------------------------------------------
  @Get('audit-log')
  @Roles(UserRole.OWNER)
  @ApiOperation({ summary: 'Query the append-only audit log' })
  @ApiResponse({ status: 200, description: 'Paginated audit log entries' })
  async queryAuditLog(@Query() query: QueryAuditLogDto) {
    return this.auditLogService.findAll(query);
  }

  // ---------------------------------------------------------------------------
  // GET /admin/audit-log/:entity_type/:id
  // ---------------------------------------------------------------------------
  @Get('audit-log/:entityType/:id')
  @Roles(UserRole.OWNER)
  @ApiOperation({ summary: 'Full audit history for a specific entity' })
  @ApiParam({ name: 'entityType', type: String })
  @ApiParam({ name: 'id', type: Number })
  @ApiResponse({ status: 200, description: 'Audit history for entity' })
  async getEntityAuditLog(
    @Param('entityType') entityType: string,
    @Param('id', ParseIntPipe) id: number,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.auditLogService.findByEntity(entityType, id, {
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  // ---------------------------------------------------------------------------
  // GET /admin/reports/weekly-production
  // ---------------------------------------------------------------------------
  @Get('reports/weekly-production')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Get weekly production report data' })
  @ApiResponse({ status: 200, description: 'Weekly production summary' })
  async getWeeklyProductionReport(@Query() query: WeeklyReportQueryDto) {
    return this.adminService.getWeeklyProductionReport(query.weekStart);
  }

  // ---------------------------------------------------------------------------
  // POST /admin/reports/weekly-production/send
  // ---------------------------------------------------------------------------
  @Post('reports/weekly-production/send')
  @Roles(UserRole.OWNER)
  @Throttle({ default: { ttl: 60_000, limit: 5 } })
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Lock and send weekly production report' })
  @ApiResponse({ status: 200, description: 'Report locked and sent' })
  async sendWeeklyProductionReport(
    @Body() body: WeeklyReportQueryDto,
    @CurrentUser() user: JwtPayload,
    @Req() req: Request,
  ) {
    return this.adminService.lockAndSendWeeklyReport(body.weekStart, user.sub, req.ip);
  }
}
