import { Test, TestingModule } from '@nestjs/testing';
import { SalesOrdersService } from './sales-orders.service';
import { PrismaService } from '../../prisma/prisma.service';
import { ConfiguratorService } from './configurator.service';
import { FeatureFlagsService } from '../../common/config/feature-flags.service';
import { QboSyncService } from '../quickbooks/qbo-sync.service';
import { QboApiClient } from '../quickbooks/qbo-api.client';
import { TrailersService } from '../trailers/trailers.service';
import { AuditLogService } from '../admin/audit-log.service';
import { ErrorCode } from '../../common/errors';

describe('SalesOrdersService — delete + deposit', () => {
  let service: SalesOrdersService;
  let prisma: {
    salesOrder: { findUnique: jest.Mock; delete: jest.Mock; update: jest.Mock };
  };
  let qboClient: { deleteEstimate: jest.Mock; createPayment: jest.Mock };
  let qboSync: { ensureCustomer: jest.Mock };
  let audit: { create: jest.Mock };
  let flags: { isEnabled: jest.Mock };

  beforeEach(async () => {
    prisma = {
      salesOrder: {
        findUnique: jest.fn(),
        delete: jest.fn().mockResolvedValue({}),
        update: jest.fn().mockResolvedValue({}),
      },
    };
    qboClient = {
      deleteEstimate: jest.fn().mockResolvedValue(undefined),
      createPayment: jest.fn().mockResolvedValue({ Id: '165' }),
    };
    qboSync = { ensureCustomer: jest.fn().mockResolvedValue('42') };
    audit = { create: jest.fn().mockResolvedValue(undefined) };
    flags = { isEnabled: jest.fn().mockReturnValue(true) };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SalesOrdersService,
        { provide: PrismaService, useValue: prisma },
        { provide: ConfiguratorService, useValue: {} },
        { provide: FeatureFlagsService, useValue: flags },
        { provide: QboSyncService, useValue: qboSync },
        { provide: QboApiClient, useValue: qboClient },
        { provide: TrailersService, useValue: {} },
        { provide: AuditLogService, useValue: audit },
      ],
    }).compile();

    service = module.get(SalesOrdersService);
    // findOne is called at the end of recordDeposit — stub it.
    jest.spyOn(service, 'findOne').mockResolvedValue({ id: BigInt(1) } as never);
  });

  // ── delete ────────────────────────────────────────────────────────────────
  describe('remove', () => {
    it('deletes a non-converted estimate from QuickBooks AND locally', async () => {
      prisma.salesOrder.findUnique.mockResolvedValue({
        id: BigInt(1),
        soNumber: '7001',
        status: 'approved',
        trailerId: null,
        qboEstimateId: '158',
        total: 9000,
      });

      const result = await service.remove(BigInt(1), BigInt(9));

      expect(qboClient.deleteEstimate).toHaveBeenCalledWith('158');
      expect(prisma.salesOrder.delete).toHaveBeenCalledWith({ where: { id: BigInt(1) } });
      expect(audit.create).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'sales_order.deleted' }),
      );
      expect(result).toEqual({ deleted: true, id: 1 });
    });

    it('refuses to delete a converted estimate (it is a live trailer)', async () => {
      prisma.salesOrder.findUnique.mockResolvedValue({
        id: BigInt(1),
        soNumber: '7001',
        status: 'in_production',
        trailerId: BigInt(613),
        qboEstimateId: '158',
        total: 9000,
      });

      await expect(service.remove(BigInt(1), BigInt(9))).rejects.toMatchObject({
        errorCode: ErrorCode.BAD_REQUEST,
      });
      expect(prisma.salesOrder.delete).not.toHaveBeenCalled();
      expect(qboClient.deleteEstimate).not.toHaveBeenCalled();
    });

    it('still removes locally when the QBO delete fails (app is source of truth)', async () => {
      prisma.salesOrder.findUnique.mockResolvedValue({
        id: BigInt(1),
        soNumber: '7001',
        status: 'approved',
        trailerId: null,
        qboEstimateId: '158',
        total: 9000,
      });
      qboClient.deleteEstimate.mockRejectedValue(new Error('already gone'));

      const result = await service.remove(BigInt(1), BigInt(9));

      expect(prisma.salesOrder.delete).toHaveBeenCalled();
      expect(result).toEqual({ deleted: true, id: 1 });
    });
  });

  // ── deposit ─────────────────────────────────────────────────────────────
  describe('recordDeposit', () => {
    const so = {
      id: BigInt(1),
      soNumber: '7001',
      customerId: BigInt(50),
      customer: { qbCustomerId: '42' },
    };

    it('records the deposit and posts a QuickBooks Payment', async () => {
      prisma.salesOrder.findUnique.mockResolvedValue(so);

      await service.recordDeposit(BigInt(1), { amount: 2000, method: 'card' }, BigInt(9));

      expect(qboClient.createPayment).toHaveBeenCalledWith(
        expect.objectContaining({ customerRef: '42', amount: 2000 }),
      );
      expect(prisma.salesOrder.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            depositAmount: 2000,
            depositMethod: 'card',
            qboPaymentId: '165',
          }),
        }),
      );
      expect(audit.create).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'sales_order.deposit_recorded' }),
      );
    });

    it('rejects a zero or negative deposit', async () => {
      prisma.salesOrder.findUnique.mockResolvedValue(so);
      for (const amount of [0, -50]) {
        await expect(
          service.recordDeposit(BigInt(1), { amount }, BigInt(9)),
        ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
      }
      expect(prisma.salesOrder.update).not.toHaveBeenCalled();
    });

    it('records locally even when the QBO Payment fails (money was still received)', async () => {
      prisma.salesOrder.findUnique.mockResolvedValue(so);
      qboClient.createPayment.mockRejectedValue(new Error('QBO down'));

      await service.recordDeposit(BigInt(1), { amount: 2000 }, BigInt(9));

      expect(prisma.salesOrder.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ depositAmount: 2000, qboPaymentId: null }),
        }),
      );
    });

    it('syncs the customer to QBO first if they have no qbCustomerId', async () => {
      prisma.salesOrder.findUnique.mockResolvedValue({
        ...so,
        customer: { qbCustomerId: null },
      });

      await service.recordDeposit(BigInt(1), { amount: 500 }, BigInt(9));

      expect(qboSync.ensureCustomer).toHaveBeenCalledWith(BigInt(50));
      expect(qboClient.createPayment).toHaveBeenCalledWith(
        expect.objectContaining({ customerRef: '42' }),
      );
    });
  });
});
