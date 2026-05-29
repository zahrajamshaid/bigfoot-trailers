import { Test, TestingModule } from '@nestjs/testing';
import { TrailersController } from './trailers.controller';
import { TrailersService } from './trailers.service';
import { JwtPayload } from '../../common/decorators/current-user.decorator';

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

const mockTrailer = {
  id: BigInt(1),
  soNumber: 'SO-1001',
  status: 'pending_production',
  trailerModel: { id: 1, code: 'XP_14ET', displayName: '14K ET XP', series: 'xp' },
  customer: { id: BigInt(100), name: 'John Doe' },
  currentLocation: { id: 1, code: 'MULBERRY', name: 'Bigfoot Trailers Mulberry' },
  addons: [],
};

const ownerPayload: JwtPayload = {
  sub: 10,
  email: 'owner@bigfoot.com',
  role: 'owner',
  departmentId: null,
  extraDepartmentIds: [],
  iat: 0,
  exp: 0,
};

// ---------------------------------------------------------------------------
// Service mock
// ---------------------------------------------------------------------------

const mockTrailersService = {
  findAll: jest
    .fn()
    .mockResolvedValue({ trailers: [mockTrailer], total: 1, page: 1, limit: 25 }),
  create: jest.fn().mockResolvedValue({
    trailer: mockTrailer,
    stepsSummary: {
      trailerId: BigInt(1),
      series: 'xp',
      totalSteps: 12,
      firstActiveStepId: BigInt(100),
    },
  }),
  findOne: jest.fn().mockResolvedValue({ ...mockTrailer, productionSteps: [] }),
  update: jest.fn().mockResolvedValue(mockTrailer),
  setPriority: jest.fn().mockResolvedValue({ ...mockTrailer, globalPriority: 5 }),
  toggleHot: jest.fn().mockResolvedValue({ ...mockTrailer, isHot: true }),
  addAddon: jest.fn().mockResolvedValue({
    id: BigInt(50),
    addonName: 'Winch',
    notes: null,
    addedAt: new Date(),
  }),
  removeAddon: jest.fn().mockResolvedValue({ deleted: true }),
  uploadQbPdf: jest.fn().mockResolvedValue(mockTrailer),
  getSteps: jest.fn().mockResolvedValue([]),
  getHistory: jest
    .fn()
    .mockResolvedValue({ steps: [], qcInspections: [], auditLogs: [] }),
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('TrailersController', () => {
  let controller: TrailersController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [TrailersController],
      providers: [{ provide: TrailersService, useValue: mockTrailersService }],
    }).compile();

    controller = module.get<TrailersController>(TrailersController);
    jest.clearAllMocks();
  });

  describe('GET /trailers', () => {
    it('should return paginated trailer list', async () => {
      const result = await controller.findAll({ page: 1, limit: 25 });

      expect(mockTrailersService.findAll).toHaveBeenCalledWith({ page: 1, limit: 25 });
      expect(result.trailers).toHaveLength(1);
      expect(result.total).toBe(1);
    });
  });

  describe('POST /trailers', () => {
    it('should create trailer and return with workflow summary', async () => {
      const dto = { soNumber: 'SO-2001', trailerModelId: 1 };

      const result = await controller.create(dto, ownerPayload);

      expect(mockTrailersService.create).toHaveBeenCalledWith(dto, BigInt(10));
      expect(result.stepsSummary.totalSteps).toBe(12);
    });
  });

  describe('GET /trailers/:id', () => {
    it('should return trailer detail', async () => {
      const result = await controller.findOne(1);

      expect(mockTrailersService.findOne).toHaveBeenCalledWith(BigInt(1));
      expect(result.soNumber).toBe('SO-1001');
    });
  });

  describe('PATCH /trailers/:id', () => {
    it('should update trailer fields', async () => {
      await controller.update(1, { color: 'Green' });

      expect(mockTrailersService.update).toHaveBeenCalledWith(BigInt(1), {
        color: 'Green',
      });
    });
  });

  describe('PATCH /trailers/:id/priority', () => {
    it('should set global priority', async () => {
      const result = await controller.setPriority(1, { globalPriority: 5 });

      expect(mockTrailersService.setPriority).toHaveBeenCalledWith(BigInt(1), {
        globalPriority: 5,
      });
      expect(result.globalPriority).toBe(5);
    });
  });

  describe('PATCH /trailers/:id/hot', () => {
    it('should toggle isHot flag', async () => {
      const result = await controller.toggleHot(1, { isHot: true });

      expect(mockTrailersService.toggleHot).toHaveBeenCalledWith(BigInt(1), {
        isHot: true,
      });
      expect(result.isHot).toBe(true);
    });
  });

  describe('POST /trailers/:id/addons', () => {
    it('should add addon to trailer', async () => {
      const result = await controller.addAddon(1, { addonName: 'Winch' });

      expect(mockTrailersService.addAddon).toHaveBeenCalledWith(BigInt(1), {
        addonName: 'Winch',
      });
      expect(result.addonName).toBe('Winch');
    });
  });

  describe('DELETE /trailers/:id/addons/:addon_id', () => {
    it('should remove addon from trailer', async () => {
      const result = await controller.removeAddon(1, 50);

      expect(mockTrailersService.removeAddon).toHaveBeenCalledWith(BigInt(1), BigInt(50));
      expect(result.deleted).toBe(true);
    });
  });

  describe('POST /trailers/:id/qb-pdf', () => {
    it('should attach QB SO PDF', async () => {
      await controller.uploadQbPdf(1, { storageKey: 'key', storageUrl: 'url' });

      expect(mockTrailersService.uploadQbPdf).toHaveBeenCalledWith(BigInt(1), {
        storageKey: 'key',
        storageUrl: 'url',
      });
    });
  });

  describe('GET /trailers/:id/steps', () => {
    it('should return production steps', async () => {
      await controller.getSteps(1);

      expect(mockTrailersService.getSteps).toHaveBeenCalledWith(BigInt(1));
    });
  });

  describe('GET /trailers/:id/history', () => {
    it('should return trailer history', async () => {
      const result = await controller.getHistory(1);

      expect(mockTrailersService.getHistory).toHaveBeenCalledWith(BigInt(1));
      expect(result).toHaveProperty('steps');
      expect(result).toHaveProperty('qcInspections');
      expect(result).toHaveProperty('auditLogs');
    });
  });
});
