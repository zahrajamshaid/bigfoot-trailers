import { Test, TestingModule } from '@nestjs/testing';
import { SalesOrdersService } from './sales-orders.service';
import { PrismaService } from '../../prisma/prisma.service';
import { ConfiguratorService } from './configurator.service';
import { FeatureFlagsService } from '../../common/config/feature-flags.service';
import { QboSyncService } from '../quickbooks/qbo-sync.service';
import { QboApiClient } from '../quickbooks/qbo-api.client';
import { TrailersService } from '../trailers/trailers.service';
import { AuditLogService } from '../admin/audit-log.service';

// Focused on the two-way estimate sync: pushUnsyncedEstimates + syncEstimates.
describe('SalesOrdersService — estimate sync with QuickBooks', () => {
  let service: SalesOrdersService;
  let prisma: { salesOrder: { findMany: jest.Mock } };
  let qboSync: {
    pushSalesOrderEstimate: jest.Mock;
    importEstimatesFromQbo: jest.Mock;
  };
  let flags: { isEnabled: jest.Mock };

  beforeEach(async () => {
    prisma = { salesOrder: { findMany: jest.fn() } };
    qboSync = {
      pushSalesOrderEstimate: jest.fn().mockResolvedValue(undefined),
      importEstimatesFromQbo: jest
        .fn()
        .mockResolvedValue({ total: 19, created: 4, updated: 15, failed: 0 }),
    };
    flags = { isEnabled: jest.fn().mockReturnValue(true) };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SalesOrdersService,
        { provide: PrismaService, useValue: prisma },
        { provide: ConfiguratorService, useValue: {} },
        { provide: FeatureFlagsService, useValue: flags },
        { provide: QboSyncService, useValue: qboSync },
        { provide: QboApiClient, useValue: {} },
        { provide: TrailersService, useValue: {} },
        { provide: AuditLogService, useValue: {} },
      ],
    }).compile();

    service = module.get(SalesOrdersService);
  });

  it('pushUnsyncedEstimates pushes each stuck estimate and reports the tally', async () => {
    prisma.salesOrder.findMany.mockResolvedValue([
      { id: BigInt(1), soNumber: '7001' },
      { id: BigInt(2), soNumber: '7002' },
    ]);

    const result = await service.pushUnsyncedEstimates();

    expect(qboSync.pushSalesOrderEstimate).toHaveBeenCalledTimes(2);
    expect(result).toEqual({ total: 2, pushed: 2, failed: 0 });
    // Only approved-but-unsynced estimates are selected.
    const where = prisma.salesOrder.findMany.mock.calls[0][0].where;
    expect(where.status).toBe('approved');
    expect(where.syncState).toEqual({ not: 'synced' });
  });

  it('one failed push does not stop the batch', async () => {
    prisma.salesOrder.findMany.mockResolvedValue([
      { id: BigInt(1), soNumber: '7001' },
      { id: BigInt(2), soNumber: '7002' },
      { id: BigInt(3), soNumber: '7003' },
    ]);
    qboSync.pushSalesOrderEstimate.mockImplementation((id: bigint) =>
      id === BigInt(2) ? Promise.reject(new Error('QBO 400')) : Promise.resolve(),
    );

    const result = await service.pushUnsyncedEstimates();

    expect(result).toEqual({ total: 3, pushed: 2, failed: 1 });
  });

  it('pushUnsyncedEstimates is a no-op when QBO sync is disabled', async () => {
    flags.isEnabled.mockReturnValue(false);
    const result = await service.pushUnsyncedEstimates();
    expect(result).toEqual({ total: 0, pushed: 0, failed: 0 });
    expect(prisma.salesOrder.findMany).not.toHaveBeenCalled();
  });

  it('syncEstimates imports from QBO then pushes unsynced, returning both', async () => {
    prisma.salesOrder.findMany.mockResolvedValue([{ id: BigInt(1), soNumber: '7001' }]);

    const result = await service.syncEstimates(BigInt(10));

    expect(qboSync.importEstimatesFromQbo).toHaveBeenCalledWith(BigInt(10));
    expect(result).toEqual({
      imported: { total: 19, created: 4, updated: 15, failed: 0 },
      pushed: { total: 1, pushed: 1, failed: 0 },
    });
  });
});
