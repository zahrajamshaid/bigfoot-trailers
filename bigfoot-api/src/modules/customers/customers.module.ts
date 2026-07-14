import { Module } from '@nestjs/common';
import { CustomersController } from './customers.controller';
import { CustomersService } from './customers.service';
import { StorageModule } from '../storage/storage.module';
import { QuickBooksModule } from '../quickbooks/quickbooks.module';

@Module({
  imports: [StorageModule, QuickBooksModule],
  controllers: [CustomersController],
  providers: [CustomersService],
  exports: [CustomersService],
})
export class CustomersModule {}
