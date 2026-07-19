import { Test, TestingModule } from '@nestjs/testing';
import { CustomersService } from './customers.service';
import { PrismaService } from '../../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { FeatureFlagsService } from '../../common/config/feature-flags.service';
import { QboSyncService } from '../quickbooks/qbo-sync.service';

describe('CustomersService — two-way QuickBooks sync', () => {
  let service: CustomersService;
  let qboSync: {
    importCustomersFromQbo: jest.Mock;
    exportCustomersToQbo: jest.Mock;
  };

  beforeEach(async () => {
    qboSync = {
      importCustomersFromQbo: jest.fn().mockResolvedValue({ total: 5, created: 2, updated: 3 }),
      exportCustomersToQbo: jest.fn().mockResolvedValue({ total: 4, exported: 4, failed: 0 }),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        CustomersService,
        { provide: PrismaService, useValue: {} },
        { provide: StorageService, useValue: {} },
        { provide: FeatureFlagsService, useValue: {} },
        { provide: QboSyncService, useValue: qboSync },
      ],
    }).compile();

    service = module.get(CustomersService);
  });

  it('syncAll imports THEN exports, and returns both summaries', async () => {
    const order: string[] = [];
    qboSync.importCustomersFromQbo.mockImplementation(async () => {
      order.push('import');
      return { total: 5, created: 2, updated: 3 };
    });
    qboSync.exportCustomersToQbo.mockImplementation(async () => {
      order.push('export');
      return { total: 4, exported: 4, failed: 0 };
    });

    const result = await service.syncAll();

    // Import first: existing QBO customers get linked before we push app-only
    // ones, so we don't re-create a customer QBO already has.
    expect(order).toEqual(['import', 'export']);
    expect(result).toEqual({
      imported: { total: 5, created: 2, updated: 3 },
      exported: { total: 4, exported: 4, failed: 0 },
    });
  });

  it('exportToQbo pushes app customers up to QuickBooks', async () => {
    const result = await service.exportToQbo();
    expect(qboSync.exportCustomersToQbo).toHaveBeenCalledTimes(1);
    expect(result).toEqual({ total: 4, exported: 4, failed: 0 });
  });

  it('importFromQbo pulls QuickBooks customers into the app', async () => {
    const result = await service.importFromQbo();
    expect(qboSync.importCustomersFromQbo).toHaveBeenCalledTimes(1);
    expect(result).toEqual({ total: 5, created: 2, updated: 3 });
  });
});
