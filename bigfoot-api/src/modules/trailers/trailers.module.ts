import { Module } from '@nestjs/common';
import { TrailersController } from './trailers.controller';
import { TrailersService } from './trailers.service';
import { WorkflowGeneratorService } from './workflow-generator.service';

@Module({
  controllers: [TrailersController],
  providers: [TrailersService, WorkflowGeneratorService],
  exports: [TrailersService],
})
export class TrailersModule {}
