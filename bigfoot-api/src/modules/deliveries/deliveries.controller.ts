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
import { DeliveriesService } from './deliveries.service';
import { BatchesService } from './batches.service';
import {
  QueryDeliveriesDto,
  CreateDeliveryDto,
  CompleteDeliveryDto,
  CompleteFactoryPickupDto,
  FailDeliveryDto,
  UploadDeliveryPhotosDto,
  CreateBatchDto,
  UpdateBatchDto,
  CompleteBatchDto,
} from './dto';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';

@ApiTags('Deliveries')
@ApiBearerAuth('JWT')
@Controller('deliveries')
export class DeliveriesController {
  constructor(
    private readonly deliveriesService: DeliveriesService,
    private readonly batchesService: BatchesService,
  ) {}

  // ---------------------------------------------------------------------------
  // GET /deliveries
  // ---------------------------------------------------------------------------
  @Get()
  @ApiOperation({ summary: 'List deliveries with filters' })
  @ApiResponse({ status: 200, description: 'List of deliveries' })
  async findAll(@Query() query: QueryDeliveriesDto) {
    return this.deliveriesService.findAll(query);
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries — transport_manager, owner
  // ---------------------------------------------------------------------------
  @Post()
  @Roles(UserRole.TRANSPORT_MANAGER, UserRole.OWNER, UserRole.SALES)
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a delivery' })
  @ApiResponse({ status: 201, description: 'Delivery created' })
  @ApiResponse({ status: 400, description: 'DELIVERY_NOT_DISPATCHABLE' })
  async create(@Body() dto: CreateDeliveryDto, @CurrentUser() requester: JwtPayload) {
    return this.deliveriesService.create(dto, BigInt(requester.sub));
  }

  // ---------------------------------------------------------------------------
  // GET /deliveries/batches — must be BEFORE :id routes
  // ---------------------------------------------------------------------------
  @Get('batches')
  @ApiOperation({ summary: 'List delivery batches' })
  @ApiResponse({ status: 200, description: 'List of batches' })
  async findBatches() {
    return this.batchesService.findAll();
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries/batches — transport_manager, owner
  // ---------------------------------------------------------------------------
  @Post('batches')
  @Roles(UserRole.TRANSPORT_MANAGER, UserRole.OWNER)
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a new delivery batch' })
  @ApiResponse({ status: 201, description: 'Batch created' })
  async createBatch(@Body() dto: CreateBatchDto, @CurrentUser() requester: JwtPayload) {
    return this.batchesService.create(dto, BigInt(requester.sub));
  }

  // ---------------------------------------------------------------------------
  // PATCH /deliveries/batches/:id — transport_manager, owner
  // ---------------------------------------------------------------------------
  @Patch('batches/:id')
  @Roles(UserRole.TRANSPORT_MANAGER, UserRole.OWNER)
  @ApiOperation({ summary: 'Update batch (add/remove trailers while building)' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Batch updated' })
  @ApiResponse({ status: 400, description: 'BATCH_NOT_BUILDING' })
  async updateBatch(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateBatchDto,
    @CurrentUser() requester: JwtPayload,
  ) {
    return this.batchesService.update(BigInt(id), dto, BigInt(requester.sub));
  }

  // ---------------------------------------------------------------------------
  // DELETE /deliveries/batches/:id — transport_manager, owner
  // ---------------------------------------------------------------------------
  @Delete('batches/:id')
  @Roles(UserRole.TRANSPORT_MANAGER, UserRole.OWNER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Delete a batch — removes its deliveries and frees their trailers',
  })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Batch deleted' })
  @ApiResponse({ status: 404, description: 'Batch not found' })
  async deleteBatch(@Param('id', ParseIntPipe) id: number) {
    return this.batchesService.deleteBatch(BigInt(id));
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries/batches/:id/depart — transport_manager, owner
  // ---------------------------------------------------------------------------
  @Post('batches/:id/depart')
  @Roles(UserRole.TRANSPORT_MANAGER, UserRole.OWNER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Dispatch a delivery batch' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Batch dispatched' })
  async dispatchBatch(@Param('id', ParseIntPipe) id: number) {
    return this.batchesService.dispatch(BigInt(id));
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries/batches/:id/complete — driver, transport_manager, owner
  // ---------------------------------------------------------------------------
  @Post('batches/:id/complete')
  @Roles(UserRole.DRIVER, UserRole.TRANSPORT_MANAGER, UserRole.OWNER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Complete a batch — marks every trailer in it delivered' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Batch completed' })
  @ApiResponse({ status: 400, description: 'Batch not in transit / nothing to complete' })
  async completeBatch(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: CompleteBatchDto,
  ) {
    return this.batchesService.complete(BigInt(id), dto);
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries/factory-pickup/:id/complete — office, owner
  // ---------------------------------------------------------------------------
  @Post('factory-pickup/:id/complete')
  @Roles(UserRole.OFFICE, UserRole.TRANSPORT_MANAGER, UserRole.OWNER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Complete a factory pickup (records who picked up & amount collected)',
  })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Factory pickup completed' })
  async completeFactoryPickup(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: CompleteFactoryPickupDto,
  ) {
    return this.deliveriesService.completeFactoryPickup(BigInt(id), dto);
  }

  // ---------------------------------------------------------------------------
  // GET /deliveries/stock-inventory — must be BEFORE :id routes
  // ---------------------------------------------------------------------------
  @Get('stock-inventory')
  @Roles(UserRole.TRANSPORT_MANAGER, UserRole.PRODUCTION_MANAGER, UserRole.OWNER)
  @ApiOperation({ summary: 'Trailers currently parked at each stock-location yard' })
  @ApiResponse({ status: 200, description: 'Stock inventory grouped by location' })
  async getStockInventory() {
    return this.deliveriesService.getStockInventory();
  }

  // ---------------------------------------------------------------------------
  // GET /deliveries/:id
  // ---------------------------------------------------------------------------
  @Get(':id')
  @ApiOperation({ summary: 'Get a single delivery with trailer info' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Delivery detail' })
  @ApiResponse({ status: 404, description: 'Delivery not found' })
  async findOne(@Param('id', ParseIntPipe) id: number) {
    return this.deliveriesService.findOne(BigInt(id));
  }

  // ---------------------------------------------------------------------------
  // PATCH /deliveries/:id/depart — driver, transport_manager
  // ---------------------------------------------------------------------------
  @Patch(':id/depart')
  @Roles(UserRole.DRIVER, UserRole.TRANSPORT_MANAGER)
  @ApiOperation({ summary: 'Driver marks en_route' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Delivery departed' })
  async markDeparted(@Param('id', ParseIntPipe) id: number) {
    return this.deliveriesService.markDeparted(BigInt(id));
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries/:id/complete — driver, transport_manager
  // ---------------------------------------------------------------------------
  @Post(':id/complete')
  @Roles(UserRole.DRIVER, UserRole.TRANSPORT_MANAGER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Driver marks delivered with payment & photos' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Delivery completed' })
  async markComplete(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: CompleteDeliveryDto,
  ) {
    return this.deliveriesService.markComplete(BigInt(id), dto);
  }

  // ---------------------------------------------------------------------------
  // DELETE /deliveries/:id — transport_manager, owner
  // ---------------------------------------------------------------------------
  @Delete(':id')
  @Roles(UserRole.TRANSPORT_MANAGER, UserRole.OWNER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Delete a delivery — frees its trailer back to ready_for_delivery',
  })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Delivery deleted' })
  @ApiResponse({ status: 404, description: 'Delivery not found' })
  async remove(@Param('id', ParseIntPipe) id: number) {
    return this.deliveriesService.remove(BigInt(id));
  }

  // ---------------------------------------------------------------------------
  // PATCH /deliveries/:id/fail — driver, transport_manager
  // ---------------------------------------------------------------------------
  @Patch(':id/fail')
  @Roles(UserRole.DRIVER, UserRole.TRANSPORT_MANAGER)
  @ApiOperation({ summary: 'Mark delivery as failed' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 200, description: 'Delivery marked failed' })
  async markFailed(@Param('id', ParseIntPipe) id: number, @Body() dto: FailDeliveryDto) {
    return this.deliveriesService.markFailed(BigInt(id), dto);
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries/:id/photos — driver, transport_manager
  // ---------------------------------------------------------------------------
  @Post(':id/photos')
  @Roles(UserRole.DRIVER, UserRole.TRANSPORT_MANAGER)
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Upload proof/damage photos for a delivery' })
  @ApiParam({ name: 'id', type: 'number' })
  @ApiResponse({ status: 201, description: 'Photos uploaded' })
  async uploadPhotos(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UploadDeliveryPhotosDto,
  ) {
    return this.deliveriesService.uploadPhotos(BigInt(id), dto);
  }
}
