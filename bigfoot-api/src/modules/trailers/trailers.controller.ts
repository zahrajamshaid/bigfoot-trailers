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
import { TrailersService } from './trailers.service';
import {
  CreateTrailerDto,
  UpdateTrailerDto,
  QueryTrailersDto,
  CreateAddonDto,
  SetPriorityDto,
  ToggleHotDto,
  UploadQbPdfDto,
  UpdateSaleStatusDto,
  SetPaintBoothDto,
} from './dto';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';

@ApiTags('Trailers')
@ApiBearerAuth('JWT')
@Controller('trailers')
export class TrailersController {
  constructor(private readonly trailersService: TrailersService) {}

  // ---------------------------------------------------------------------------
  // GET /trailers
  // ---------------------------------------------------------------------------
  @Get()
  @ApiOperation({ summary: 'List trailers with filters and pagination' })
  @ApiResponse({ status: 200, description: 'Paginated trailer list' })
  async findAll(@Query() query: QueryTrailersDto) {
    return this.trailersService.findAll(query);
  }

  // ---------------------------------------------------------------------------
  // POST /trailers — owner + production_manager
  // ---------------------------------------------------------------------------
  @Post()
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({
    summary: 'Create a new trailer SO and auto-generate 12 workflow steps',
  })
  @ApiResponse({ status: 201, description: 'Trailer created with workflow steps' })
  @ApiResponse({ status: 409, description: 'SO number already exists' })
  @ApiResponse({ status: 403, description: 'Forbidden — insufficient role' })
  async create(@Body() dto: CreateTrailerDto, @CurrentUser() requester: JwtPayload) {
    return this.trailersService.create(dto, BigInt(requester.sub));
  }

  // ---------------------------------------------------------------------------
  // GET /trailers/:id
  // ---------------------------------------------------------------------------
  @Get(':id')
  @ApiOperation({ summary: 'Get full trailer detail with current step' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Trailer detail' })
  @ApiResponse({ status: 404, description: 'Trailer not found' })
  async findOne(@Param('id', ParseIntPipe) id: number) {
    return this.trailersService.findOne(BigInt(id));
  }

  // ---------------------------------------------------------------------------
  // PATCH /trailers/:id — update color, notes, status
  // ---------------------------------------------------------------------------
  @Patch(':id')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Update trailer fields (color, notes, status)' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Trailer updated' })
  @ApiResponse({ status: 404, description: 'Trailer not found' })
  async update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateTrailerDto) {
    return this.trailersService.update(BigInt(id), dto);
  }

  // ---------------------------------------------------------------------------
  // PATCH /trailers/:id/priority — production_manager, owner
  // ---------------------------------------------------------------------------
  @Patch(':id/priority')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Set global priority on a trailer' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Priority updated' })
  @ApiResponse({ status: 404, description: 'Trailer not found' })
  async setPriority(@Param('id', ParseIntPipe) id: number, @Body() dto: SetPriorityDto) {
    return this.trailersService.setPriority(BigInt(id), dto);
  }

  // ---------------------------------------------------------------------------
  // PATCH /trailers/:id/hot — toggle is_hot
  // ---------------------------------------------------------------------------
  @Patch(':id/hot')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Toggle is_hot flag on a trailer' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Hot flag updated' })
  @ApiResponse({ status: 404, description: 'Trailer not found' })
  async toggleHot(@Param('id', ParseIntPipe) id: number, @Body() dto: ToggleHotDto) {
    return this.trailersService.toggleHot(BigInt(id), dto);
  }

  // ---------------------------------------------------------------------------
  // PATCH /trailers/:id/sale-status — owner + sales + production_manager
  // ---------------------------------------------------------------------------
  @Patch(':id/sale-status')
  @Roles(UserRole.OWNER, UserRole.SALES, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({
    summary: 'Set the sale status (available / sale_pending / sold)',
    description:
      'Marking a trailer sold requires a buyer name (soldToName) unless the ' +
      'trailer already has a customer. Restricted to owner, sales and ' +
      'production_manager roles.',
  })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Sale status updated' })
  @ApiResponse({
    status: 400,
    description: 'A buyer name is required to mark a trailer sold',
  })
  @ApiResponse({ status: 403, description: 'Forbidden — insufficient role' })
  @ApiResponse({ status: 404, description: 'Trailer not found' })
  async updateSaleStatus(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateSaleStatusDto,
  ) {
    return this.trailersService.updateSaleStatus(BigInt(id), dto);
  }

  // ---------------------------------------------------------------------------
  // PATCH /trailers/:id/paint-booth — swap a trailer between PAINT_A / PAINT_B
  // ---------------------------------------------------------------------------
  @Patch(':id/paint-booth')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({
    summary: 'Manually move a trailer between PAINT_A and PAINT_B',
    description:
      'Production manager / owner override of the size-based auto-routing. ' +
      'The trailer\'s paint production_step is repointed to the target booth; ' +
      'status / queue position are preserved. PAINT_A rejects trailers ≥25ft.',
  })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Paint booth updated' })
  @ApiResponse({ status: 400, description: '≥25ft trailers cannot be on PAINT_A' })
  @ApiResponse({ status: 403, description: 'Forbidden — insufficient role' })
  @ApiResponse({ status: 404, description: 'Trailer not found' })
  async setPaintBooth(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: SetPaintBoothDto,
  ) {
    return this.trailersService.setPaintBooth(BigInt(id), dto.paintBoothCode);
  }

  // ---------------------------------------------------------------------------
  // POST /trailers/:id/mark-completed — sales-facing terminal action.
  //
  // Completes the open scheduled / in_transit Delivery (sets deliveredAt) and
  // flips the trailer to delivered in one transaction. Idempotent — already-
  // delivered trailers return without changes.
  // ---------------------------------------------------------------------------
  @Post(':id/mark-completed')
  @Roles(UserRole.OWNER, UserRole.SALES, UserRole.PRODUCTION_MANAGER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Sales-facing terminal completion — picked up or delivered',
    description:
      'Closes the trailer\'s open delivery and marks the trailer delivered. ' +
      'Same end state regardless of pickup vs delivery intent. Restricted to ' +
      'owner, sales, and production_manager.',
  })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Trailer completed (or already was)' })
  @ApiResponse({ status: 404, description: 'Trailer not found' })
  async markCompleted(
    @Param('id', ParseIntPipe) id: number,
    @CurrentUser() requester: JwtPayload,
  ) {
    return this.trailersService.markCompleted(BigInt(id), BigInt(requester.sub));
  }

  // ---------------------------------------------------------------------------
  // POST /trailers/:id/addons
  // ---------------------------------------------------------------------------
  @Post(':id/addons')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Add an addon to a trailer' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 201, description: 'Addon added' })
  @ApiResponse({ status: 404, description: 'Trailer not found' })
  async addAddon(@Param('id', ParseIntPipe) id: number, @Body() dto: CreateAddonDto) {
    return this.trailersService.addAddon(BigInt(id), dto);
  }

  // ---------------------------------------------------------------------------
  // DELETE /trailers/:id/addons/:addon_id
  // ---------------------------------------------------------------------------
  @Delete(':id/addons/:addon_id')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Remove an addon from a trailer' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiParam({ name: 'addon_id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Addon removed' })
  @ApiResponse({ status: 404, description: 'Addon not found' })
  async removeAddon(
    @Param('id', ParseIntPipe) id: number,
    @Param('addon_id', ParseIntPipe) addonId: number,
  ) {
    return this.trailersService.removeAddon(BigInt(id), BigInt(addonId));
  }

  // ---------------------------------------------------------------------------
  // POST /trailers/:id/qb-pdf
  // ---------------------------------------------------------------------------
  @Post(':id/qb-pdf')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER, UserRole.OFFICE)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Attach QuickBooks SO PDF to a trailer' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'QB PDF attached' })
  @ApiResponse({ status: 404, description: 'Trailer not found' })
  async uploadQbPdf(@Param('id', ParseIntPipe) id: number, @Body() dto: UploadQbPdfDto) {
    return this.trailersService.uploadQbPdf(BigInt(id), dto);
  }

  // ---------------------------------------------------------------------------
  // DELETE /trailers/:id — owner + production_manager (destructive)
  // ---------------------------------------------------------------------------
  @Delete(':id')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Permanently delete a trailer and all related records',
    description:
      'Cascades through production steps, QC inspections/photos, deliveries, ' +
      'worker messages, location receipts, SMS logs, push notifications, and ' +
      'stall alerts. Restricted to owner and production_manager roles.',
  })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Trailer and all related records deleted' })
  @ApiResponse({
    status: 403,
    description: 'Forbidden — owner or production_manager role required',
  })
  @ApiResponse({ status: 404, description: 'Trailer not found' })
  async delete(@Param('id', ParseIntPipe) id: number) {
    return this.trailersService.deleteTrailer(BigInt(id));
  }

  // ---------------------------------------------------------------------------
  // GET /trailers/:id/steps
  // ---------------------------------------------------------------------------
  @Get(':id/steps')
  @ApiOperation({ summary: 'Get all production steps for a trailer' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'All production steps' })
  @ApiResponse({ status: 404, description: 'Trailer not found' })
  async getSteps(@Param('id', ParseIntPipe) id: number) {
    return this.trailersService.getSteps(BigInt(id));
  }

  // ---------------------------------------------------------------------------
  // GET /trailers/:id/history
  // ---------------------------------------------------------------------------
  @Get(':id/history')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER, UserRole.QC_INSPECTOR)
  @ApiOperation({ summary: 'Full audit + QC + step history for a trailer' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Trailer history' })
  @ApiResponse({ status: 404, description: 'Trailer not found' })
  async getHistory(@Param('id', ParseIntPipe) id: number) {
    return this.trailersService.getHistory(BigInt(id));
  }
}
