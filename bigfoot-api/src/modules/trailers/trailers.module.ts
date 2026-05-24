import { Module } from '@nestjs/common';
import { TrailersController } from './trailers.controller';
import { TrailersService } from './trailers.service';
import { WorkflowGeneratorService } from './workflow-generator.service';
import { StorageModule } from '../storage/storage.module';

@Module({
  imports: [StorageModule],
  controllers: [TrailersController],
  providers: [TrailersService, WorkflowGeneratorService],
  exports: [TrailersService],
})
export class TrailersModule {}
