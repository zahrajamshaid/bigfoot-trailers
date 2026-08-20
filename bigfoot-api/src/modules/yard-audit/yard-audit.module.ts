import { Module } from '@nestjs/common';
import { SupportModule } from '../support/support.module';
import { YardAuditController } from './yard-audit.controller';
import { YardAuditService } from './yard-audit.service';

@Module({
  imports: [SupportModule],
  controllers: [YardAuditController],
  providers: [YardAuditService],
})
export class YardAuditModule {}
