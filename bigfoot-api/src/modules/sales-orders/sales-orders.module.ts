import { Module } from '@nestjs/common';
import { SalesOrdersController } from './sales-orders.controller';
import { SalesOrdersService } from './sales-orders.service';
import { ConfiguratorService } from './configurator.service';
import { PackingSlipService } from './packing-slip.service';
import { EstimateReconciliationService } from './estimate-reconciliation.service';
import { QuickBooksModule } from '../quickbooks/quickbooks.module';
import { TrailersModule } from '../trailers/trailers.module';
import { AdminModule } from '../admin/admin.module';
import { NotificationsModule } from '../notifications/notifications.module';

/**
 * Phase 2 — app-native Sales Orders + configurator. Inert until
 * SALES_ORDERS_ENABLED. Imports QuickBooksModule so the approve → QBO Estimate
 * push can reuse the QBO client, and TrailersModule so accept → convert can
 * spawn the production trailer (the work order).
 */
@Module({
  imports: [QuickBooksModule, TrailersModule, AdminModule, NotificationsModule],
  controllers: [SalesOrdersController],
  providers: [
    SalesOrdersService,
    ConfiguratorService,
    PackingSlipService,
    EstimateReconciliationService,
  ],
  exports: [SalesOrdersService, ConfiguratorService],
})
export class SalesOrdersModule {}
