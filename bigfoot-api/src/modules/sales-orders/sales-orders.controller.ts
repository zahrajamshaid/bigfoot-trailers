import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Post,
  Query,
  Res,
} from '@nestjs/common';
import type { Response } from 'express';
import { ApiBearerAuth, ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { SalesOrderStatus } from '@prisma/client';
import { CurrentUser, JwtPayload, Roles, UserRole } from '../../common/decorators';
import { AppError, ErrorCode } from '../../common/errors';
import {
  FeatureFlag,
  FeatureFlagsService,
} from '../../common/config/feature-flags.service';
import { SalesOrdersService } from './sales-orders.service';
import { PackingSlipService } from './packing-slip.service';
import { EstimateReconciliationService } from './estimate-reconciliation.service';
import {
  CreateSalesOrderDto,
  PreviewSalesOrderDto,
} from './dto/create-sales-order.dto';
import { RecordDepositDto } from './dto/record-deposit.dto';

@ApiTags('Sales Orders')
@ApiBearerAuth('JWT')
@Controller('sales-orders')
export class SalesOrdersController {
  constructor(
    private readonly service: SalesOrdersService,
    private readonly packingSlip: PackingSlipService,
    private readonly flags: FeatureFlagsService,
    private readonly reconciliation: EstimateReconciliationService,
  ) {}

  private assertEnabled(): void {
    if (!this.flags.isEnabled(FeatureFlag.SALES_ORDERS)) {
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        'Sales Orders are disabled (SALES_ORDERS_ENABLED is off)',
      );
    }
  }

  // The configurator catalog (models + options + fees) in one call.
  @Get('catalog')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Configurator catalog: models + options + fees' })
  getCatalog() {
    this.assertEnabled();
    return this.service.getCatalog();
  }

  // Preview a configuration's lines + subtotal (no persistence).
  @Post('preview')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Preview composed lines + subtotal for a configuration' })
  @ApiResponse({ status: 200, description: 'Composed lines + preview subtotal' })
  preview(@Body() dto: PreviewSalesOrderDto) {
    this.assertEnabled();
    return this.service.preview(dto);
  }

  // Create a draft Sales Order from a configuration.
  @Post()
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Create a draft Sales Order' })
  create(@Body() dto: CreateSalesOrderDto, @CurrentUser() user: JwtPayload) {
    this.assertEnabled();
    return this.service.createDraft(dto, BigInt(user.sub));
  }

  @Get()
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'List Sales Orders (optionally by status)' })
  list(@Query('status') status?: SalesOrderStatus) {
    this.assertEnabled();
    return this.service.list(status);
  }

  // Pull estimates FROM QuickBooks into the app (two-way sync).
  @Post('import-from-qbo')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Import estimates created in QuickBooks into the app' })
  importFromQbo(@CurrentUser() user: JwtPayload) {
    this.assertEnabled();
    return this.service.importFromQbo(BigInt(user.sub));
  }

  // Two-way estimate sync: import estimates from QBO + push any app estimates
  // that failed to reach QBO. Pure data sync (no conversion). Returns
  // { imported, pushed }.
  @Post('sync')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Two-way estimate sync with QuickBooks' })
  syncEstimates(@CurrentUser() user: JwtPayload) {
    this.assertEnabled();
    return this.service.syncEstimates(BigInt(user.sub));
  }

  @Get(':id')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Get a Sales Order with its lines' })
  findOne(@Param('id', ParseIntPipe) id: number) {
    this.assertEnabled();
    return this.service.findOne(BigInt(id));
  }

  // Download the QuickBooks estimate PDF for this Sales Order.
  @Get(':id/estimate-pdf')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Download the QuickBooks estimate PDF' })
  async estimatePdf(
    @Param('id', ParseIntPipe) id: number,
    @Res() res: Response,
  ): Promise<void> {
    this.assertEnabled();
    const pdf = await this.service.getEstimatePdf(BigInt(id));
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader(
      'Content-Disposition',
      `inline; filename="estimate-${id}.pdf"`,
    );
    res.send(pdf);
  }

  // WORK ORDER — the Sales Order with every dollar amount stripped. This is the
  // shop copy, so the production/jig/floor roles can read it. QBO has no
  // packing-slip API, so we render it from the SO lines.
  @Get(':id/packing-slip')
  @Roles(
    UserRole.OWNER,
    UserRole.OFFICE,
    UserRole.SALES,
    UserRole.PRODUCTION_MANAGER,
    UserRole.QC_INSPECTOR,
    UserRole.WORKER,
    UserRole.PARTS,
    UserRole.PURCHASING,
    UserRole.TRANSPORT_MANAGER,
    UserRole.DRIVER,
  )
  @ApiOperation({ summary: 'Work order PDF (packing slip — no prices)' })
  async packingSlipPdf(
    @Param('id', ParseIntPipe) id: number,
    @Res() res: Response,
  ): Promise<void> {
    this.assertEnabled();
    const { pdf, soNumber } = await this.packingSlip.generate(BigInt(id));
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader(
      'Content-Disposition',
      `inline; filename="${soNumber}.pdf"`,
    );
    res.send(pdf);
  }

  // SALES ORDER — the same document WITH the money. Role-gated: only
  // admin/office/sales may see dollar figures; the floor gets the work order.
  @Get(':id/sales-order-pdf')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Sales Order PDF (priced — office/sales only)' })
  async salesOrderPdf(
    @Param('id', ParseIntPipe) id: number,
    @Res() res: Response,
  ): Promise<void> {
    this.assertEnabled();
    const { pdf, soNumber } = await this.packingSlip.generate(BigInt(id), {
      withPrices: true,
    });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader(
      'Content-Disposition',
      `inline; filename="SO-${soNumber}.pdf"`,
    );
    res.send(pdf);
  }

  // Approve a draft → allocate SO number + push a QBO Estimate.
  // Sales can approve: this only allocates the SO# and pushes a QBO ESTIMATE
  // (a quote, not a commitment) — the core sales action, and the reason Quick
  // Estimate exists. It's also what makes the estimate sendable, and `send`
  // already allows SALES. Turning the quote into a production trailer is a
  // separate, committed step (`accept`), which stays OWNER/OFFICE.
  @Post(':id/approve')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Approve a draft Sales Order (pushes a QBO Estimate)' })
  approve(@Param('id', ParseIntPipe) id: number, @CurrentUser() user: JwtPayload) {
    this.assertEnabled();
    return this.service.approve(BigInt(id), BigInt(user.sub));
  }

  // Retry a failed QBO Estimate push (the sync-chip retry button). Sales owns
  // the estimate they approved, so they own recovering its sync too.
  @Post(':id/retry-sync')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Retry the QuickBooks Estimate push for an approved SO' })
  retrySync(@Param('id', ParseIntPipe) id: number) {
    this.assertEnabled();
    return this.service.retrySync(BigInt(id));
  }

  // Email the estimate to the customer via QuickBooks (QBO "Send").
  @Post(':id/send')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Email the QuickBooks estimate to the customer' })
  send(@Param('id', ParseIntPipe) id: number) {
    this.assertEnabled();
    return this.service.sendEstimate(BigInt(id));
  }

  // Accept the estimate → mark QBO Accepted + convert to a production trailer.
  // Sales can convert too — they close the deal with the customer, and they
  // already own the rest of the estimate lifecycle (create/approve/send/delete).
  @Post(':id/accept')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Accept the estimate and convert it to a production trailer' })
  accept(@Param('id', ParseIntPipe) id: number, @CurrentUser() user: JwtPayload) {
    this.assertEnabled();
    return this.service.accept(BigInt(id), BigInt(user.sub));
  }

  // Delete an estimate (accidental one) — removes it from QuickBooks too. A
  // converted estimate (already a production trailer) is refused with a message
  // to edit that trailer into a stock build instead.
  @Delete(':id')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Delete an estimate (also deletes it from QuickBooks)' })
  remove(@Param('id', ParseIntPipe) id: number, @CurrentUser() user: JwtPayload) {
    this.assertEnabled();
    return this.service.remove(BigInt(id), BigInt(user.sub));
  }

  // Record an initial deposit received on the trailer + post it to QuickBooks
  // as a customer Payment. Owner/office/sales.
  @Post(':id/deposit')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Record an initial deposit (posts a QuickBooks Payment)' })
  recordDeposit(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: RecordDepositDto,
    @CurrentUser() user: JwtPayload,
  ) {
    this.assertEnabled();
    return this.service.recordDeposit(BigInt(id), dto, BigInt(user.sub));
  }

  // Run the estimate-acceptance reconciliation now instead of waiting for the
  // nightly job: ask QBO which of our open estimates the customer has accepted
  // (e.g. via the email link), convert those, and notify the office. Returns a
  // summary { checked, converted, stillPending, failed }.
  @Post('reconcile-acceptance')
  @Roles(UserRole.OWNER, UserRole.OFFICE)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Reconcile estimate acceptance from QuickBooks now' })
  reconcileAcceptance() {
    this.assertEnabled();
    return this.reconciliation.reconcileOnce();
  }
}
