import { Test } from '@nestjs/testing';
import { ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditLogService } from '../admin/audit-log.service';
import { TrailerOptionsService } from './trailer-options.service';

/**
 * The rules Drew asked for, pinned:
 *
 *   • The department that FITS an option must acknowledge it before it can
 *     complete its step. Other departments see it and move on.
 *   • An option added after the build started is flagged for the production
 *     manager — it must not disappear silently into the build.
 */
describe('TrailerOptionsService', () => {
  let service: TrailerOptionsService;
  let prisma: {
    trailer: { findUnique: jest.Mock };
    productionStep: { findFirst: jest.Mock; findUnique: jest.Mock };
    trailerAddon: {
      create: jest.Mock;
      findMany: jest.Mock;
      findUnique: jest.Mock;
      update: jest.Mock;
    };
    trailerAddonDept: { findMany: jest.Mock; findUnique: jest.Mock; update: jest.Mock };
  };

  beforeEach(async () => {
    prisma = {
      trailer: { findUnique: jest.fn() },
      productionStep: { findFirst: jest.fn(), findUnique: jest.fn() },
      trailerAddon: {
        create: jest.fn(),
        findMany: jest.fn(),
        findUnique: jest.fn(),
        update: jest.fn(),
      },
      trailerAddonDept: {
        findMany: jest.fn(),
        findUnique: jest.fn(),
        update: jest.fn(),
      },
    };
    const mod = await Test.createTestingModule({
      providers: [
        TrailerOptionsService,
        { provide: PrismaService, useValue: prisma },
        { provide: AuditLogService, useValue: { create: jest.fn() } },
      ],
    }).compile();
    service = mod.get(TrailerOptionsService);
  });

  describe('assertOptionsAcknowledged — the gate on the line', () => {
    it('blocks the step when this department has an unacknowledged option', async () => {
      prisma.trailerAddonDept.findMany.mockResolvedValue([
        { addon: { addonName: 'Extra D-rings (x2)' } },
      ]);

      await expect(service.assertOptionsAcknowledged(7n, 3)).rejects.toMatchObject({
        errorCode: ErrorCode.OPTIONS_NOT_ACKNOWLEDGED,
      });
    });

    it('names the option so the worker knows what to fit', async () => {
      prisma.trailerAddonDept.findMany.mockResolvedValue([
        { addon: { addonName: 'Extra D-rings (x2)' } },
      ]);
      await expect(service.assertOptionsAcknowledged(7n, 3)).rejects.toThrow(
        /Extra D-rings/,
      );
    });

    it('lets the step through once acknowledged', async () => {
      prisma.trailerAddonDept.findMany.mockResolvedValue([]);
      await expect(service.assertOptionsAcknowledged(7n, 3)).resolves.toBeUndefined();
    });

    it('only looks at THIS department — others can skip options they do not fit', async () => {
      prisma.trailerAddonDept.findMany.mockResolvedValue([]);
      await service.assertOptionsAcknowledged(7n, 99);
      expect(prisma.trailerAddonDept.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            departmentId: 99, // scoped to the caller's department
            acknowledgedAt: null,
            addon: { trailerId: 7n },
          }),
        }),
      );
    });
  });

  describe('addOption — mid-build changes must not go unnoticed', () => {
    const addon = { id: 1n, departments: [{ department: { code: 'JIG_1' } }] };

    it('flags an option added AFTER the build started, with the step it got past', async () => {
      prisma.trailer.findUnique.mockResolvedValue({
        id: 5n,
        soNumber: '6995',
        status: 'in_production',
      });
      prisma.productionStep.findFirst.mockResolvedValue({
        stepOrder: 6,
        departmentId: 4,
        department: { code: 'PAINT_A' },
      });
      prisma.trailerAddon.create.mockResolvedValue(addon);

      await service.addOption(5n, { addonName: 'Extra D-rings' }, 9n);

      expect(prisma.trailerAddon.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            addedDuringProduction: true,
            addedAtStepOrder: 6, // it got past PAINT — this is the alert
            addedAtDepartmentId: 4,
            addedByUserId: 9n,
          }),
        }),
      );
    });

    it('assigns EVERY department that has to fit part of the option', async () => {
      prisma.trailer.findUnique.mockResolvedValue({
        id: 5n,
        soNumber: '6995',
        status: 'in_production',
      });
      prisma.productionStep.findFirst.mockResolvedValue({
        stepOrder: 2,
        departmentId: 3,
        department: { code: 'XP_JIG' },
      });
      prisma.trailerAddon.create.mockResolvedValue(addon);

      // D-rings: welded at JIG (3), touched up at PAINT (8). Duplicate is
      // de-duped — one department is one responsibility.
      await service.addOption(
        5n,
        { addonName: 'Extra D-rings', installDepartmentIds: [3, 8, 3] },
        9n,
      );

      expect(prisma.trailerAddon.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            departments: {
              create: [{ departmentId: 3 }, { departmentId: 8 }],
            },
          }),
        }),
      );
    });

    // Every option is a change to an order that already exists, so it always
    // reaches the production manager's review box — including on a trailer
    // that hasn't started yet. That case used to be skipped silently, which is
    // exactly how an added option went unseen.
    it('flags an option added BEFORE the build starts (still needs review)', async () => {
      prisma.trailer.findUnique.mockResolvedValue({
        id: 5n,
        soNumber: '6995',
        status: 'pending_production',
      });
      prisma.productionStep.findFirst.mockResolvedValue(null);
      prisma.trailerAddon.create.mockResolvedValue(addon);

      await service.addOption(5n, { addonName: 'Spare tire' }, 9n);

      expect(prisma.trailerAddon.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            addedDuringProduction: true,
            // Nothing was active, so there's no step it "got past".
            addedAtStepOrder: null,
            addedAtDepartmentId: null,
          }),
        }),
      );
    });

    it.each([
      ['pending_production', null],
      ['in_production', { stepOrder: 3, departmentId: 8, department: { code: 'XP_FIN' } }],
      ['ready_for_delivery', null],
      ['delivered', null],
    ])('flags the option whatever state the trailer is in: %s', async (status, step) => {
      prisma.trailer.findUnique.mockResolvedValue({
        id: 5n,
        soNumber: '6995',
        status,
      });
      prisma.productionStep.findFirst.mockResolvedValue(step);
      prisma.trailerAddon.create.mockResolvedValue(addon);

      await service.addOption(5n, { addonName: 'Spare tire' }, 9n);

      expect(prisma.trailerAddon.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ addedDuringProduction: true }),
        }),
      );
    });
  });

  describe('listPendingProductionManagerReview — the roll-back signal', () => {
    /// SO 6770: options added while the trailer sits at XP_FIN (step 3), but
    /// they must be fitted by XP_JIG (step 1) — which is already COMPLETE.
    /// That worker will never see the option, so unless the PM sends the
    /// trailer back it gets built wrong. This is the exact case Drew described.
    const trailerAt = (opts: {
      jigStatus: 'complete' | 'active';
      jigAcknowledged?: boolean;
    }) => [
      {
        id: 1n,
        addonName: 'Extra D-rings',
        notes: null,
        addedAt: new Date(),
        // Added while the build was already at XP_FIN.
        addedAtStepOrder: 3,
        addedAtDepartment: { code: 'XP_FIN' },
        addedByUser: { fullName: 'Sales' },
        departments: [
          {
            departmentId: 1,
            acknowledgedAt: opts.jigAcknowledged ? new Date() : null,
            department: { id: 1, code: 'XP_JIG', displayName: 'XP Jig' },
          },
        ],
        trailer: {
          id: 386n,
          soNumber: '6770',
          status: 'in_production',
          trailerModel: { code: 'XP_14ET' },
          productionSteps: [
            {
              id: 10n,
              stepOrder: 1,
              status: opts.jigStatus,
              departmentId: 1,
              department: { id: 1, code: 'XP_JIG', displayName: 'XP Jig' },
            },
            {
              id: 11n,
              stepOrder: 3,
              status: 'active',
              departmentId: 2,
              department: { id: 2, code: 'XP_FIN', displayName: 'XP Finish' },
            },
          ],
        },
      },
    ];

    it('flags a roll-back when a department that still owes work is already PASSED', async () => {
      prisma.trailerAddon.findMany.mockResolvedValue(
        trailerAt({ jigStatus: 'complete' }),
      );

      const [row] = await service.listPendingProductionManagerReview();

      // XP_JIG's step is complete and it never acknowledged → it will never
      // see this option. The trailer is on course to be built wrong.
      expect(row.needsRollback).toBe(true);
      expect(row.missedDepartments).toEqual(['XP_JIG']);
    });

    it('does NOT flag a roll-back when the owing department is still ahead', async () => {
      // Same option, but XP_JIG hasn't been reached yet — it'll see it in time.
      prisma.trailerAddon.findMany.mockResolvedValue(
        trailerAt({ jigStatus: 'active' }),
      );

      const [row] = await service.listPendingProductionManagerReview();

      expect(row.needsRollback).toBe(false);
      expect(row.missedDepartments).toEqual([]);
    });

    it('does NOT flag a roll-back once that department has acknowledged', async () => {
      prisma.trailerAddon.findMany.mockResolvedValue(
        trailerAt({ jigStatus: 'complete', jigAcknowledged: true }),
      );

      const [row] = await service.listPendingProductionManagerReview();

      expect(row.needsRollback).toBe(false);
    });
  });

  describe('listForStep — what the worker sees', () => {
    it('marks only this department’s options as must-acknowledge', async () => {
      prisma.productionStep.findUnique.mockResolvedValue({
        trailerId: 5n,
        departmentId: 3, // JIG
      });
      prisma.trailerAddon.findMany.mockResolvedValue([
        // Mine, not fitted yet.
        {
          id: 1n,
          addonName: 'D-rings',
          departments: [
            { id: 11n, departmentId: 3, acknowledgedAt: null, department: { code: 'XP_JIG' } },
            // Also needs PAINT — but that is PAINT's problem, not mine.
            { id: 12n, departmentId: 8, acknowledgedAt: null, department: { code: 'PAINT_A' } },
          ],
        },
        // Someone else's entirely.
        {
          id: 2n,
          addonName: 'Paint black',
          departments: [
            { id: 13n, departmentId: 8, acknowledgedAt: null, department: { code: 'PAINT_A' } },
          ],
        },
        // Mine, already done.
        {
          id: 3n,
          addonName: 'Winch plate',
          departments: [
            { id: 14n, departmentId: 3, acknowledgedAt: new Date(), department: { code: 'XP_JIG' } },
          ],
        },
      ]);

      const rows = await service.listForStep(1n);

      // Mine, not yet done → I must tick it.
      expect(rows[0]).toMatchObject({ mustAcknowledge: true, forThisDepartment: true });
      // Someone else fits it → informational, I can skip it.
      expect(rows[1]).toMatchObject({ mustAcknowledge: false, forThisDepartment: false });
      // Mine, already done → no longer blocking.
      expect(rows[2]).toMatchObject({ mustAcknowledge: false, forThisDepartment: true });
    });
  });
});
