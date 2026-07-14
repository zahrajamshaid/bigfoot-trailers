import { Module } from '@nestjs/common';
import { TrailersController } from './trailers.controller';
import { TrailersService } from './trailers.service';
import { TrailerOptionsService } from './trailer-options.service';
import { TrailerOptionsController } from './trailer-options.controller';
import { AdminModule } from '../admin/admin.module';
import { WorkflowGeneratorService } from './workflow-generator.service';
import { StorageModule } from '../storage/storage.module';

@Module({
  imports: [StorageModule, AdminModule],
  controllers: [TrailersController, TrailerOptionsController],
  providers: [TrailersService, WorkflowGeneratorService, TrailerOptionsService],
  exports: [TrailersService, TrailerOptionsService],
})
export class TrailersModule {}
