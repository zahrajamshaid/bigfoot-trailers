import {
  Controller,
  Get,
  Post,
  Query,
  Res,
  Logger,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { randomUUID, createHmac, timingSafeEqual } from 'crypto';
import type { Response } from 'express';
import { ConfigService } from '@nestjs/config';
import { Public, Roles, UserRole } from '../../common/decorators';
import { QboSyncService } from './qbo-sync.service';
import { AppError, ErrorCode } from '../../common/errors';
import {
  FeatureFlag,
  FeatureFlagsService,
} from '../../common/config/feature-flags.service';
import { QboAuthService } from './qbo-auth.service';
import { QboApiClient } from './qbo-api.client';

/**
 * QuickBooks OAuth connect/callback + health. All owner-gated except the
 * callback, which Intuit hits directly (no JWT) — it's protected by a signed
 * `state` value we mint and verify.
 */
@ApiTags('QuickBooks')
@ApiBearerAuth('JWT')
@Controller('quickbooks')
export class QuickBooksController {
  private readonly logger = new Logger('QuickBooks');

  constructor(
    private readonly flags: FeatureFlagsService,
    private readonly auth: QboAuthService,
    private readonly client: QboApiClient,
    private readonly sync: QboSyncService,
    private readonly config: ConfigService,
  ) {}

  private assertEnabled(): void {
    if (!this.flags.isEnabled(FeatureFlag.QBO_SYNC)) {
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        'QuickBooks integration is disabled (QBO_SYNC_ENABLED is off)',
      );
    }
  }

  /**
   * Sign the CSRF `state` with the JWT secret so the callback can verify the
   * consent request originated from us without needing server-side session
   * storage. Format: `<nonce>.<hmac>`.
   */
  private signState(): string {
    const nonce = randomUUID();
    const sig = createHmac('sha256', this.config.get<string>('JWT_SECRET') ?? '')
      .update(nonce)
      .digest('hex');
    return `${nonce}.${sig}`;
  }

  private verifyState(state: string): boolean {
    const [nonce, sig] = state.split('.');
    if (!nonce || !sig) return false;
    const expected = createHmac('sha256', this.config.get<string>('JWT_SECRET') ?? '')
      .update(nonce)
      .digest('hex');
    try {
      return timingSafeEqual(Buffer.from(sig), Buffer.from(expected));
    } catch {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // GET /quickbooks/connect — owner starts the OAuth flow
  // ---------------------------------------------------------------------------
  // Owner/office/sales can all start the connect flow — completing it still
  // requires real QuickBooks credentials at Intuit's consent screen, so this
  // button alone grants nobody access to the books.
  @Get('connect')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'Get the Intuit consent URL to connect QuickBooks' })
  @ApiResponse({ status: 200, description: 'Authorization URL to open in a browser' })
  getConnectUrl(): { authorizationUrl: string } {
    this.assertEnabled();
    return { authorizationUrl: this.auth.getAuthorizationUrl(this.signState()) };
  }

  // ---------------------------------------------------------------------------
  // GET /quickbooks/callback — Intuit redirects here (no JWT; state-verified)
  // ---------------------------------------------------------------------------
  @Public()
  @Get('callback')
  @ApiOperation({ summary: 'OAuth2 redirect target — exchanges the auth code' })
  async callback(
    @Query('code') code: string,
    @Query('realmId') realmId: string,
    @Query('state') state: string,
    @Res() res: Response,
  ): Promise<void> {
    this.assertEnabled();
    if (!code || !realmId) {
      throw new AppError(ErrorCode.BAD_REQUEST, 'Missing code or realmId in callback');
    }
    if (!state || !this.verifyState(state)) {
      throw new AppError(ErrorCode.UNAUTHORIZED, 'Invalid OAuth state');
    }
    await this.auth.handleCallback(code, realmId);
    // Simple confirmation page — the owner did this in a browser tab.
    res
      .status(200)
      .send(
        '<html><body style="font-family:sans-serif;padding:2rem">' +
          '<h2>QuickBooks connected ✓</h2>' +
          '<p>You can close this tab and return to the app.</p>' +
          '</body></html>',
      );
  }

  // ---------------------------------------------------------------------------
  // GET /quickbooks/health — connection status + a live CompanyInfo probe
  // ---------------------------------------------------------------------------
  @Get('health')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @ApiOperation({ summary: 'QuickBooks connection status + company probe' })
  async health(): Promise<{
    enabled: boolean;
    connected: boolean;
    realmId?: string;
    environment: string;
    accessExpiresAt?: Date;
    refreshExpiresAt?: Date;
    companyName?: string;
    probeError?: string;
  }> {
    const enabled = this.flags.isEnabled(FeatureFlag.QBO_SYNC);
    const status = await this.auth.status();
    if (!enabled || !status.connected) {
      return { enabled, ...status };
    }
    // Live probe so "connected" isn't just "we have a token row".
    try {
      const info = await this.client.getCompanyInfo();
      return { enabled, ...status, companyName: info.companyName };
    } catch (e) {
      return {
        enabled,
        ...status,
        probeError: e instanceof Error ? e.message : 'probe failed',
      };
    }
  }

  // ---------------------------------------------------------------------------
  // GET /quickbooks/qbo/customers — live read-through of QBO customers
  // (diagnostic / catalog-preview; the real import lands in the catalog module)
  // ---------------------------------------------------------------------------
  @Get('qbo/customers')
  @Roles(UserRole.OWNER, UserRole.OFFICE)
  @ApiOperation({ summary: 'List customers directly from QuickBooks' })
  async qboCustomers(): Promise<{ count: number; customers: unknown[] }> {
    this.assertEnabled();
    const customers = await this.client.listCustomers();
    return { count: customers.length, customers };
  }

  // ---------------------------------------------------------------------------
  // GET /quickbooks/qbo/items — live read-through of QBO products/services
  // ---------------------------------------------------------------------------
  @Get('qbo/items')
  @Roles(UserRole.OWNER, UserRole.OFFICE)
  @ApiOperation({ summary: 'List products/services directly from QuickBooks' })
  async qboItems(): Promise<{ count: number; items: unknown[] }> {
    this.assertEnabled();
    const items = await this.client.listItems();
    return { count: items.length, items };
  }

  // ---------------------------------------------------------------------------
  // POST /quickbooks/import-catalog — Slice 1. Pull QBO products/services into
  // the app's catalog: link models (+ prices), upsert options + fees.
  // Idempotent — re-running creates zero duplicates.
  // ---------------------------------------------------------------------------
  @Post('import-catalog')
  @Roles(UserRole.OWNER, UserRole.OFFICE)
  @ApiOperation({
    summary: 'Import models/options/fees + prices from QuickBooks (idempotent)',
  })
  async importCatalog() {
    this.assertEnabled();
    return this.sync.importCatalogFromQbo();
  }

  // ---------------------------------------------------------------------------
  // POST /quickbooks/qbo/test-estimate — create a sample Estimate in QBO
  // (proof-of-push; real configurator→estimate mapping lands with SalesOrders)
  // ---------------------------------------------------------------------------
  @Post('qbo/test-estimate')
  @Roles(UserRole.OWNER)
  @ApiOperation({ summary: 'Create a sample Estimate in QuickBooks (sandbox proof)' })
  async testEstimate(): Promise<{
    created: boolean;
    estimateId?: string;
    docNumber?: string;
    total?: number;
    tax?: number;
    customer?: string;
  }> {
    this.assertEnabled();
    // Auto-pick a real sandbox customer + a priced item so the estimate is
    // meaningful. QBO computes the tax + total from the pushed line.
    const [customers, items] = await Promise.all([
      this.client.listCustomers(),
      this.client.listItems(),
    ]);
    const customer = customers[0];
    const item = items.find((i) => (i.UnitPrice ?? 0) > 0) ?? items[0];
    if (!customer || !item) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'Sandbox has no customer/item to build a test estimate from',
      );
    }
    const qty = 1;
    const unitPrice = item.UnitPrice ?? 100;
    const estimate = await this.client.createEstimate({
      CustomerRef: { value: customer.Id },
      PrivateNote: `bigfoot-test-${randomUUID()}`,
      Line: [
        {
          DetailType: 'SalesItemLineDetail',
          Amount: qty * unitPrice,
          Description: `Bigfoot Phase 2 test — ${item.Name}`,
          SalesItemLineDetail: {
            ItemRef: { value: item.Id },
            Qty: qty,
            UnitPrice: unitPrice,
          },
        },
      ],
    });
    return {
      created: true,
      estimateId: estimate.Id,
      docNumber: estimate.DocNumber,
      total: estimate.TotalAmt,
      tax: estimate.TxnTaxDetail?.TotalTax,
      customer: customer.DisplayName,
    };
  }

  // ---------------------------------------------------------------------------
  // POST /quickbooks/disconnect — owner drops the connection
  // ---------------------------------------------------------------------------
  @Post('disconnect')
  @Roles(UserRole.OWNER)
  @ApiOperation({ summary: 'Revoke + forget the QuickBooks connection' })
  async disconnect(): Promise<{ disconnected: true }> {
    this.assertEnabled();
    await this.auth.disconnect();
    return { disconnected: true };
  }
}
