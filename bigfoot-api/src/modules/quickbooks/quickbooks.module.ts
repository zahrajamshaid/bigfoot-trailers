import { Module } from '@nestjs/common';
import { QuickBooksController } from './quickbooks.controller';
import { QboAuthService } from './qbo-auth.service';
import { QboApiClient } from './qbo-api.client';
import { QboSyncService } from './qbo-sync.service';

/**
 * Phase 2 — QuickBooks Online integration.
 *
 * This slice ships only the OAuth foundation: connect/callback/health/
 * disconnect + the token store + a thin API client. Push queue, webhooks,
 * and the nightly reconciliation job land in later slices. Everything is
 * inert until QBO_SYNC_ENABLED is flipped on.
 *
 * PrismaService comes from the global PrismaModule; FeatureFlagsService from
 * the global FeatureFlagsModule; ConfigService from the global ConfigModule.
 */
@Module({
  controllers: [QuickBooksController],
  providers: [QboAuthService, QboApiClient, QboSyncService],
  exports: [QboAuthService, QboApiClient, QboSyncService],
})
export class QuickBooksModule {}
