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
import { ProductionService } from './production.service';
import { CompleteStepDto, ReorderQueueDto } from './dto';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';

@ApiTags('Production')
@ApiBearerAuth('JWT')
@Controller('production')
export class ProductionController {
  constructor(private readonly productionService: ProductionService) {}

  // ---------------------------------------------------------------------------
  // GET /production/departments
  // ---------------------------------------------------------------------------
  @Get('departments')
  @ApiOperation({ summary: 'List all departments' })
  @ApiResponse({ status: 200, description: 'List of departments' })
  async getDepartments() {
    return this.productionService.getDepartments();
  }

  // ---------------------------------------------------------------------------
  // GET /production/queue/all — production_manager, owner
  // ---------------------------------------------------------------------------
  @Get('queue/all')
  @Roles(UserRole.PRODUCTION_MANAGER, UserRole.OWNER)
  @ApiOperation({ summary: 'Get all department queues' })
  @ApiResponse({ status: 200, description: 'All queue items grouped by department' })
  async getAllQueues() {
    return this.productionService.getAllQueues();
  }

  // ---------------------------------------------------------------------------
  // GET /production/queue/:dept_id
  // ---------------------------------------------------------------------------
  @Get('queue/:dept_id')
  @ApiOperation({ summary: 'Get production queue for a department' })
  @ApiParam({ name: 'dept_id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Queue items for the department' })
  @ApiResponse({ status: 404, description: 'Department not found' })
  async getQueueByDepartment(
    @Param('dept_id', ParseIntPipe) deptId: number,
    @Query('includeWaiting') includeWaiting?: string,
  ) {
    return this.productionService.getQueueByDepartment(
      deptId,
      includeWaiting === 'true' || includeWaiting === '1',
    );
  }

  // ---------------------------------------------------------------------------
  // GET /production/trailers/:trailer_id/upstream-checks
  // ---------------------------------------------------------------------------
  @Get('trailers/:trailer_id/upstream-checks')
  @ApiOperation({
    summary: 'Worker self-check results for a trailer (all upstream non-QC steps)',
  })
  @ApiParam({ name: 'trailer_id', type: 'number' })
  async getUpstreamChecksForTrailer(
    @Param('trailer_id', ParseIntPipe) trailerId: number,
  ) {
    return this.productionService.getUpstreamChecksForTrailer(BigInt(trailerId));
  }

  // ---------------------------------------------------------------------------
  // GET /production/steps/:step_id/checklist-items
  // ---------------------------------------------------------------------------
  @Get('steps/:step_id/checklist-items')
  @ApiOperation({ summary: 'Upstream self-check items for this step' })
  @ApiParam({ name: 'step_id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Checklist items for the step' })
  async getChecklistItemsForStep(
    @Param('step_id', ParseIntPipe) stepId: number,
  ) {
    return this.productionService.getChecklistItemsForStep(BigInt(stepId));
  }

  // ---------------------------------------------------------------------------
  // POST /production/steps/:step_id/complete — worker, production_manager, owner
  // ---------------------------------------------------------------------------
  @Post('steps/:step_id/complete')
  @Roles(UserRole.WORKER, UserRole.PRODUCTION_MANAGER, UserRole.OWNER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Mark a production step as complete' })
  @ApiParam({ name: 'step_id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Step completed' })
  @ApiResponse({ status: 400, description: 'STEP_NOT_ACTIVE or STEP_ALREADY_COMPLETE' })
  async completeStep(
    @Param('step_id', ParseIntPipe) stepId: number,
    @Body() dto: CompleteStepDto,
    @CurrentUser() requester: JwtPayload,
  ) {
    return this.productionService.completeStep(
      BigInt(stepId),
      BigInt(requester.sub),
      dto.notes,
      dto.checklistResults,
    );
  }

  // ---------------------------------------------------------------------------
  // POST /production/steps/:step_id/reverse — worker (own), production_manager, owner
  // ---------------------------------------------------------------------------
  @Post('steps/:step_id/reverse')
  @Roles(UserRole.WORKER, UserRole.PRODUCTION_MANAGER, UserRole.OWNER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Reverse a recently completed step' })
  @ApiParam({ name: 'step_id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Step reversed' })
  @ApiResponse({ status: 403, description: 'STEP_REVERSAL_NOT_AUTHORIZED' })
  async reverseStep(
    @Param('step_id', ParseIntPipe) stepId: number,
    @CurrentUser() requester: JwtPayload,
  ) {
    return this.productionService.reverseStep(
      BigInt(stepId),
      BigInt(requester.sub),
      requester.role,
    );
  }

  // ---------------------------------------------------------------------------
  // PATCH /production/queue/:dept_id/reorder — production_manager, owner
  // ---------------------------------------------------------------------------
  @Patch('queue/:dept_id/reorder')
  @Roles(UserRole.PRODUCTION_MANAGER, UserRole.OWNER)
  @ApiOperation({ summary: 'Reorder the queue for a department' })
  @ApiParam({ name: 'dept_id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Queue reordered' })
  async reorderQueue(
    @Param('dept_id', ParseIntPipe) deptId: number,
    @Body() dto: ReorderQueueDto,
  ) {
    return this.productionService.reorderQueue(deptId, dto.stepIds);
  }
}
