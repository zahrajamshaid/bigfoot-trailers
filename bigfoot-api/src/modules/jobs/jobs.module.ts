import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { StorageModule } from '../storage/storage.module';
import { StallDetectorProcessor } from './stall-detector.processor';
import { SmsQueueProcessor } from './sms-queue.processor';
import { ReportGeneratorProcessor } from './report-generator.processor';
import { OrphanCleanupProcessor } from './orphan-cleanup.processor';

@Module({
  imports: [NotificationsModule, StorageModule],
  providers: [
    StallDetectorProcessor,
    SmsQueueProcessor,
    ReportGeneratorProcessor,
    OrphanCleanupProcessor,
  ],
})
export class JobsModule {}
