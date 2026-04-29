import { Module } from '@nestjs/common';
import { DeliveriesController } from './deliveries.controller';
import { LocationReceiptsController } from './location-receipts.controller';
import { DeliveriesService } from './deliveries.service';
import { BatchesService } from './batches.service';
import { LocationReceiptsService } from './location-receipts.service';
import { NotificationsModule } from '../notifications/notifications.module';

@Module({
  imports: [NotificationsModule],
  controllers: [DeliveriesController, LocationReceiptsController],
  providers: [DeliveriesService, BatchesService, LocationReceiptsService],
  exports: [DeliveriesService],
})
export class DeliveriesModule {}
