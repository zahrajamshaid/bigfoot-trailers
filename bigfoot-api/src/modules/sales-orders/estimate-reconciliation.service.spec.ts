import { Test, TestingModule } from '@nestjs/testing';
import { EstimateReconciliationService } from './estimate-reconciliation.service';
import { PrismaService } from '../../prisma/prisma.service';
import { QboApiClient } from '../quickbooks/qbo-api.client';
import { AuditLogService } from '../admin/audit-log.service';
import { NotificationsService } from '../notifications/notifications.service';
import { FeatureFlag, FeatureFlagsService } from '../../common/config/feature-flags.service';
import { SalesOrdersService } from './sales-orders.service';

// Two open estimates we're still waiting on: one the customer has now accepted
// in QBO, one still pending.
const acceptedSo = {
  id: BigInt(30),
  soNumber: '123445692',
  qboEstimateId: '158',
  salesRepUserId: BigInt(164),
  createdByUserId: BigInt(164),
  customer: { name: 'Test Buyer' },
};
const pendingSo = {
  id: BigInt(31),
  soNumber: '123445693',
  qboEstimateId: '159',
  salesRepUserId: null,
  createdByUserId: BigInt(99),
  customer: { name: 'Waiting Wanda' },
};

describe('EstimateReconciliationService', () => {
  let service: EstimateReconciliationService;
  let prisma: { salesOrder: { findMany: jest.Mock } };
  let qbo: { getEstimate: jest.Mock };
  let salesOrders: { accept: jest.Mock };
  let notifications: { onEstimateAccepted: jest.Mock };
  let audit: { create: jest.Mock };
  let flags: { isEnabled: jest.Mock };

  beforeEach(async () => {
    prisma = { salesOrder: { findMany: jest.fn() } };
    qbo = { getEstimate: jest.fn() };
    salesOrders = { accept: jest.fn() };
    notifications = { onEstimateAccepted: jest.fn().mockResolvedValue(undefined) };
    audit = { create: jest.fn().mockResolvedValue(undefined) };
    flags = { isEnabled: jest.fn().mockReturnValue(true) };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        EstimateReconciliationService,
        { provide: PrismaService, useValue: prisma },
        { provide: QboApiClient, useValue: qbo },
        { provide: SalesOrdersService, useValue: salesOrders },
        { provide: NotificationsService, useValue: notifications },
        { provide: AuditLogService, useValue: audit },
        { provide: FeatureFlagsService, useValue: flags },
      ],
    }).compile();

    service = module.get(EstimateReconciliationService);
  });

  it('converts an estimate the customer accepted in QBO and notifies the office', async () => {
    prisma.salesOrder.findMany.mockResolvedValue([acceptedSo]);
    qbo.getEstimate.mockResolvedValue({ Id: '158', TxnStatus: 'Accepted' });
    salesOrders.accept.mockResolvedValue({ id: BigInt(30), trailerId: BigInt(500) });

    const summary = await service.reconcileOnce();

    expect(summary).toEqual({ checked: 1, converted: 1, stillPending: 0, failed: 0 });
    // Accepted in QBO already → convert WITHOUT re-pushing the acceptance.
    expect(salesOrders.accept).toHaveBeenCalledWith(BigInt(30), BigInt(164), {
      skipQboAccept: true,
    });
    // Office gets told, with the freshly-created trailer.
    expect(notifications.onEstimateAccepted).toHaveBeenCalledWith(
      expect.objectContaining({
        soNumber: '123445692',
        customerName: 'Test Buyer',
        trailerId: BigInt(500),
      }),
    );
    // The 'why' is recorded.
    expect(audit.create).toHaveBeenCalledWith(
      expect.objectContaining({ action: 'sales_order.accepted_via_qbo' }),
    );
  });

  it('leaves an estimate the customer has NOT accepted untouched', async () => {
    prisma.salesOrder.findMany.mockResolvedValue([pendingSo]);
    qbo.getEstimate.mockResolvedValue({ Id: '159', TxnStatus: 'Pending' });

    const summary = await service.reconcileOnce();

    expect(summary).toEqual({ checked: 1, converted: 0, stillPending: 1, failed: 0 });
    expect(salesOrders.accept).not.toHaveBeenCalled();
    expect(notifications.onEstimateAccepted).not.toHaveBeenCalled();
  });

  it('handles a mix and never lets one bad estimate stop the rest', async () => {
    const boomSo = { ...pendingSo, id: BigInt(32), soNumber: '123445694', qboEstimateId: '160' };
    prisma.salesOrder.findMany.mockResolvedValue([acceptedSo, boomSo, pendingSo]);
    qbo.getEstimate.mockImplementation((qId: string) => {
      if (qId === '158') return Promise.resolve({ Id: qId, TxnStatus: 'Accepted' });
      if (qId === '160') return Promise.reject(new Error('QBO 500'));
      return Promise.resolve({ Id: qId, TxnStatus: 'Pending' });
    });
    salesOrders.accept.mockResolvedValue({ id: BigInt(30), trailerId: BigInt(500) });

    const summary = await service.reconcileOnce();

    expect(summary).toEqual({ checked: 3, converted: 1, stillPending: 1, failed: 1 });
    expect(notifications.onEstimateAccepted).toHaveBeenCalledTimes(1);
  });

  it('still notifies when the accepted estimate converts without a trailer (no model match)', async () => {
    prisma.salesOrder.findMany.mockResolvedValue([acceptedSo]);
    qbo.getEstimate.mockResolvedValue({ Id: '158', TxnStatus: 'Accepted' });
    salesOrders.accept.mockResolvedValue({ id: BigInt(30), trailerId: null });

    const summary = await service.reconcileOnce();

    expect(summary.converted).toBe(1);
    expect(notifications.onEstimateAccepted).toHaveBeenCalledWith(
      expect.objectContaining({ trailerId: undefined }),
    );
  });

  it('the nightly cron is inert when QBO sync is disabled', async () => {
    flags.isEnabled.mockImplementation((f: FeatureFlag) => f !== FeatureFlag.QBO_SYNC);

    await service.nightly();

    expect(prisma.salesOrder.findMany).not.toHaveBeenCalled();
  });

  it('the nightly cron swallows a total failure rather than crashing the scheduler', async () => {
    prisma.salesOrder.findMany.mockRejectedValue(new Error('DB down'));
    await expect(service.nightly()).resolves.toBeUndefined();
  });
});
