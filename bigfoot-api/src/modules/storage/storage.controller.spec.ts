import { Test, TestingModule } from '@nestjs/testing';
import { StorageController } from './storage.controller';
import { StorageService } from './storage.service';

describe('StorageController', () => {
  let controller: StorageController;

  const mockStorageService = {
    generateUploadUrl: jest.fn(),
    generateDownloadUrl: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [StorageController],
      providers: [{ provide: StorageService, useValue: mockStorageService }],
    }).compile();

    controller = module.get<StorageController>(StorageController);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  describe('presignUpload', () => {
    it('should delegate to storageService.generateUploadUrl', async () => {
      const dto = { fileType: 'qc_photo', trailerId: 100, fileName: 'test.jpg' };
      mockStorageService.generateUploadUrl.mockResolvedValue({
        uploadUrl: 'https://signed.url',
        storageKey: 'qc/100/uuid.jpg',
        expiresIn: 900,
        maxSizeBytes: 10485760,
        contentType: 'image/jpeg',
      });

      const result = await controller.presignUpload(dto);

      expect(mockStorageService.generateUploadUrl).toHaveBeenCalledWith({
        fileType: 'qc_photo',
        trailerId: 100,
        fileName: 'test.jpg',
      });
      expect(result.uploadUrl).toBe('https://signed.url');
      expect(result.storageKey).toBe('qc/100/uuid.jpg');
    });
  });

  describe('presignDownload', () => {
    it('should delegate to storageService.generateDownloadUrl', async () => {
      mockStorageService.generateDownloadUrl.mockResolvedValue({
        downloadUrl: 'https://signed.url',
        storageKey: 'qc/100/uuid.jpg',
        expiresIn: 900,
      });

      const result = await controller.presignDownload('qc/100/uuid.jpg');

      expect(mockStorageService.generateDownloadUrl).toHaveBeenCalledWith(
        'qc/100/uuid.jpg',
      );
      expect(result.downloadUrl).toBe('https://signed.url');
    });
  });
});
