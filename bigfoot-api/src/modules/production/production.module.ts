import { Module } from '@nestjs/common';
import { ProductionController } from './production.controller';
import { ProductionService } from './production.service';
import { NotificationsModule } from '../notifications/notifications.module';
import { TrailersModule } from '../trailers/trailers.module';

@Module({
  imports: [NotificationsModule, TrailersModule],
  controllers: [ProductionController],
  providers: [ProductionService],
  exports: [ProductionService],
})
export class ProductionModule {}
