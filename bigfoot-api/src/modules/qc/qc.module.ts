import { Module } from '@nestjs/common';
import { QcController } from './qc.controller';
import { QcService } from './qc.service';
import { ReworkRoutingService } from './rework-routing.service';
import { NotificationsModule } from '../notifications/notifications.module';

@Module({
  imports: [NotificationsModule],
  controllers: [QcController],
  providers: [QcService, ReworkRoutingService],
  exports: [QcService, ReworkRoutingService],
})
export class QcModule {}
