import { Test, TestingModule } from '@nestjs/testing';
import { ProductionService } from './production.service';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { TrailerOptionsService } from '../trailers/trailer-options.service';
import { ErrorCode } from '../../common/errors';

// ---------------------------------------------------------------------------
// A QC stage may only be signed off through a QC inspection, which REQUIRES a
// photo of the stage.
//
// The hole this pins: completeStep used to accept a QC step. It branched on
// `isQcStep` to skip the checklist, then marked the step complete — so
// POST /production/steps/:id/complete would pass a QC stage with no photo and
// no inspection record at all, straight around QcService's photo requirement.
//
// Nothing legitimate went that way (the worker queue excludes QC departments,
// and submitInspection completes the QC step itself), so the path is now shut.
// ---------------------------------------------------------------------------

const qcStep = {
  id: BigInt(200),
  trailerId: BigInt(1),
  departmentId: 15,
  stepOrder: 2,
  status: 'active',
  isRework: false,
  department: { id: 15, code: 'QC_1', displayName: 'Quality Control 1', isQcStep: true },
  trailer: { trailerModel: { series: 'xp' }, addons: [] },
};

const finalQcStep = {
  ...qcStep,
  id: BigInt(212),
  departmentId: 20,
  department: { id: 20, code: 'FINAL_QC', displayName: 'Final QC', isQcStep: true },
};

describe('ProductionService.completeStep — QC steps cannot skip the photo', () => {
  let service: ProductionService;
  let prisma: { productionStep: { findUnique: jest.Mock } };
  let options: { assertOptionsAcknowledged: jest.Mock };

  beforeEach(async () => {
    prisma = { productionStep: { findUnique: jest.fn() } };
    options = { assertOptionsAcknowledged: jest.fn().mockResolvedValue(undefined) };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ProductionService,
        { provide: PrismaService, useValue: prisma },
        { provide: NotificationsService, useValue: {} },
        { provide: TrailerOptionsService, useValue: options },
      ],
    }).compile();

    service = module.get(ProductionService);
  });

  it.each([
    ['a QC_1 step', qcStep],
    ['a FINAL_QC step', finalQcStep],
  ])('refuses to complete %s directly — it must go through a QC inspection', async (_label, step) => {
    prisma.productionStep.findUnique.mockResolvedValue(step);

    await expect(
      service.completeStep(step.id, BigInt(7), 'looks fine to me'),
    ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
  });

  it('names the QC inspection as the way through, so the worker knows what to do', async () => {
    prisma.productionStep.findUnique.mockResolvedValue(qcStep);

    await expect(
      service.completeStep(qcStep.id, BigInt(7)),
    ).rejects.toThrow(/QC inspection \(with photos\)/i);
  });

  it('rejects the QC step BEFORE doing any completion work', async () => {
    prisma.productionStep.findUnique.mockResolvedValue(qcStep);

    await expect(service.completeStep(qcStep.id, BigInt(7))).rejects.toThrow();

    // If any of this had run, a QC stage would be partway signed off with no photo.
    expect(options.assertOptionsAcknowledged).not.toHaveBeenCalled();
    expect(prisma).not.toHaveProperty('productionStepCheck.createMany');
  });
});
