import { Test, TestingModule } from '@nestjs/testing';
import { OrphanCleanupProcessor } from './orphan-cleanup.processor';
import { PrismaService } from '../../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';

describe('OrphanCleanupProcessor', () => {
  let processor: OrphanCleanupProcessor;

  const mockPrisma = {
    qcPhoto: { findMany: jest.fn() },
    deliveryPhoto: { findMany: jest.fn() },
    trailer: { findMany: jest.fn() },
  };

  const mockStorageService = {
    listObjects: jest.fn(),
    deleteObject: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        OrphanCleanupProcessor,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: StorageService, useValue: mockStorageService },
      ],
    }).compile();

    processor = module.get<OrphanCleanupProcessor>(OrphanCleanupProcessor);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(processor).toBeDefined();
  });

  describe('cleanup', () => {
    it('should delete orphaned QC photos', async () => {
      mockStorageService.listObjects.mockImplementation((prefix: string) => {
        if (prefix === 'qc/') return ['qc/1/a.jpg', 'qc/1/b.jpg', 'qc/1/orphan.jpg'];
        return [];
      });

      // a.jpg and b.jpg are referenced, orphan.jpg is not
      mockPrisma.qcPhoto.findMany.mockResolvedValue([
        { storageKey: 'qc/1/a.jpg' },
        { storageKey: 'qc/1/b.jpg' },
      ]);
      mockPrisma.deliveryPhoto.findMany.mockResolvedValue([]);
      mockPrisma.trailer.findMany.mockResolvedValue([]);
      mockStorageService.deleteObject.mockResolvedValue(undefined);

      const count = await processor.cleanup();

      expect(count).toBe(1);
      expect(mockStorageService.deleteObject).toHaveBeenCalledWith('qc/1/orphan.jpg');
    });

    it('should delete orphaned delivery photos', async () => {
      mockStorageService.listObjects.mockImplementation((prefix: string) => {
        if (prefix === 'delivery/') return ['delivery/1/proof.jpg', 'delivery/1/orphan.png'];
        return [];
      });

      mockPrisma.qcPhoto.findMany.mockResolvedValue([]);
      mockPrisma.deliveryPhoto.findMany.mockResolvedValue([
        { storageKey: 'delivery/1/proof.jpg' },
      ]);
      mockPrisma.trailer.findMany.mockResolvedValue([]);
      mockStorageService.deleteObject.mockResolvedValue(undefined);

      const count = await processor.cleanup();

      expect(count).toBe(1);
      expect(mockStorageService.deleteObject).toHaveBeenCalledWith('delivery/1/orphan.png');
    });

    it('should delete orphaned SO PDFs', async () => {
      mockStorageService.listObjects.mockImplementation((prefix: string) => {
        if (prefix === 'so-pdf/') return ['so-pdf/100/doc.pdf', 'so-pdf/200/orphan.pdf'];
        return [];
      });

      mockPrisma.qcPhoto.findMany.mockResolvedValue([]);
      mockPrisma.deliveryPhoto.findMany.mockResolvedValue([]);
      mockPrisma.trailer.findMany.mockResolvedValue([
        { qbSoPdfStorageKey: 'so-pdf/100/doc.pdf' },
      ]);
      mockStorageService.deleteObject.mockResolvedValue(undefined);

      const count = await processor.cleanup();

      expect(count).toBe(1);
      expect(mockStorageService.deleteObject).toHaveBeenCalledWith('so-pdf/200/orphan.pdf');
    });

    it('should not delete anything if all files are referenced', async () => {
      mockStorageService.listObjects.mockImplementation((prefix: string) => {
        if (prefix === 'qc/') return ['qc/1/a.jpg'];
        return [];
      });

      mockPrisma.qcPhoto.findMany.mockResolvedValue([
        { storageKey: 'qc/1/a.jpg' },
      ]);
      mockPrisma.deliveryPhoto.findMany.mockResolvedValue([]);
      mockPrisma.trailer.findMany.mockResolvedValue([]);

      const count = await processor.cleanup();

      expect(count).toBe(0);
      expect(mockStorageService.deleteObject).not.toHaveBeenCalled();
    });

    it('should handle empty storage gracefully', async () => {
      mockStorageService.listObjects.mockResolvedValue([]);

      const count = await processor.cleanup();

      expect(count).toBe(0);
    });

    it('should handle delete errors gracefully and continue', async () => {
      mockStorageService.listObjects.mockImplementation((prefix: string) => {
        if (prefix === 'qc/') return ['qc/1/orphan1.jpg', 'qc/1/orphan2.jpg'];
        return [];
      });

      mockPrisma.qcPhoto.findMany.mockResolvedValue([]);
      mockPrisma.deliveryPhoto.findMany.mockResolvedValue([]);
      mockPrisma.trailer.findMany.mockResolvedValue([]);

      mockStorageService.deleteObject
        .mockRejectedValueOnce(new Error('S3 error'))
        .mockResolvedValueOnce(undefined);

      const count = await processor.cleanup();

      // Only 1 succeeded, 1 failed
      expect(count).toBe(1);
      expect(mockStorageService.deleteObject).toHaveBeenCalledTimes(2);
    });
  });
});
