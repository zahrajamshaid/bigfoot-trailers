import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { StorageService, VALID_FILE_TYPES } from './storage.service';
import { ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';

// Mock the S3 SDK modules
jest.mock('@aws-sdk/client-s3', () => {
  return {
    S3Client: jest.fn().mockImplementation(() => ({
      send: jest.fn().mockResolvedValue({
        Contents: [{ Key: 'qc/1/test.jpg' }],
      }),
    })),
    PutObjectCommand: jest.fn(),
    GetObjectCommand: jest.fn(),
    DeleteObjectCommand: jest.fn(),
    ListObjectsV2Command: jest.fn(),
  };
});

jest.mock('@aws-sdk/s3-request-presigner', () => ({
  getSignedUrl: jest.fn().mockResolvedValue('https://spaces.example.com/signed-url'),
}));

describe('StorageService', () => {
  let service: StorageService;

  const mockConfigService = {
    get: jest.fn((key: string, defaultVal?: string) => {
      const config: Record<string, string> = {
        DO_SPACES_ENDPOINT: 'https://nyc3.digitaloceanspaces.com',
        DO_SPACES_REGION: 'nyc3',
        DO_SPACES_KEY: 'test-key',
        DO_SPACES_SECRET: 'test-secret',
        DO_SPACES_BUCKET: 'bigfoot-test',
        DO_SPACES_CDN_URL: 'https://cdn.example.com',
      };
      return config[key] ?? defaultVal ?? undefined;
    }),
  };

  // Prisma stub — every generateUploadUrl call looks up the trailer's SO
  // number to build the storage path. Default mock returns a deterministic
  // SO derived from the trailer id so per-test regex assertions stay specific.
  const mockPrisma: { trailer: { findUnique: jest.Mock } } = {
    trailer: {
      findUnique: jest.fn(({ where }: { where: { id: bigint } }) =>
        Promise.resolve({ soNumber: `SO-${where.id.toString()}` }),
      ),
    },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        StorageService,
        { provide: ConfigService, useValue: mockConfigService },
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<StorageService>(StorageService);
    service.onModuleInit();
    jest.clearAllMocks();
    // Re-install the default findUnique impl after clearAllMocks
    mockPrisma.trailer.findUnique.mockImplementation(
      ({ where }: { where: { id: bigint } }) =>
        Promise.resolve({ soNumber: `SO-${where.id.toString()}` }),
    );
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // =========================================================================
  // generateUploadUrl
  // =========================================================================
  describe('generateUploadUrl', () => {
    it('should generate a pre-signed upload URL for qc_photo', async () => {
      const result = await service.generateUploadUrl({
        fileType: 'qc_photo',
        trailerId: 100,
        fileName: 'inspection.jpg',
      });

      expect(result.uploadUrl).toBe('https://spaces.example.com/signed-url');
      expect(result.storageKey).toMatch(/^qc\/SO-100\/[a-f0-9-]+\.jpg$/);
      expect(result.expiresIn).toBe(900);
      expect(result.maxSizeBytes).toBe(10 * 1024 * 1024);
      expect(result.contentType).toBe('image/jpeg');
    });

    it('should generate a pre-signed upload URL for so_pdf', async () => {
      const result = await service.generateUploadUrl({
        fileType: 'so_pdf',
        trailerId: 200,
        fileName: 'SO-1001.pdf',
      });

      expect(result.storageKey).toMatch(/^so-pdf\/SO-200\/[a-f0-9-]+\.pdf$/);
      expect(result.maxSizeBytes).toBe(25 * 1024 * 1024);
      expect(result.contentType).toBe('application/pdf');
    });

    it('should generate a pre-signed upload URL for delivery_photo', async () => {
      const result = await service.generateUploadUrl({
        fileType: 'delivery_photo',
        trailerId: 300,
        fileName: 'proof.png',
      });

      expect(result.storageKey).toMatch(/^delivery\/SO-300\/[a-f0-9-]+\.png$/);
      expect(result.contentType).toBe('image/png');
    });

    it('should generate a pre-signed upload URL for damage_photo', async () => {
      const result = await service.generateUploadUrl({
        fileType: 'damage_photo',
        trailerId: 400,
        fileName: 'damage.webp',
      });

      expect(result.storageKey).toMatch(/^damage\/SO-400\/[a-f0-9-]+\.webp$/);
      expect(result.contentType).toBe('image/webp');
    });

    it('should throw PRESIGN_INVALID_FILE_TYPE for unknown file_type', async () => {
      await expect(
        service.generateUploadUrl({
          fileType: 'malware',
          trailerId: 100,
          fileName: 'bad.exe',
        }),
      ).rejects.toThrow('Invalid file_type');
    });

    it('should throw for invalid extension', async () => {
      await expect(
        service.generateUploadUrl({
          fileType: 'qc_photo',
          trailerId: 100,
          fileName: 'script.exe',
        }),
      ).rejects.toThrow('Invalid file extension');
    });

    it('should throw when so_pdf has a photo extension', async () => {
      await expect(
        service.generateUploadUrl({
          fileType: 'so_pdf',
          trailerId: 100,
          fileName: 'fake.jpg',
        }),
      ).rejects.toThrow('requires a PDF extension');
    });

    it('should throw when photo type has PDF extension', async () => {
      await expect(
        service.generateUploadUrl({
          fileType: 'qc_photo',
          trailerId: 100,
          fileName: 'doc.pdf',
        }),
      ).rejects.toThrow('requires a photo extension');
    });

    it('should throw for file with no extension', async () => {
      await expect(
        service.generateUploadUrl({
          fileType: 'qc_photo',
          trailerId: 100,
          fileName: 'noext',
        }),
      ).rejects.toThrow('Invalid file extension');
    });

    it('should handle case-insensitive extensions', async () => {
      const result = await service.generateUploadUrl({
        fileType: 'qc_photo',
        trailerId: 100,
        fileName: 'PHOTO.JPG',
      });

      expect(result.storageKey).toMatch(/\.jpg$/);
    });

    it('should sanitise unsafe characters in the SO number for the S3 path', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValueOnce({
        soNumber: 'SO 99/A&B',
      });

      const result = await service.generateUploadUrl({
        fileType: 'qc_photo',
        trailerId: 500,
        fileName: 'photo.jpg',
      });

      // Spaces, slashes, and `&` are replaced with `_` so the path stays flat.
      expect(result.storageKey).toMatch(/^qc\/SO_99_A_B\/[a-f0-9-]+\.jpg$/);
    });

    it('should throw NOT_FOUND when the trailer does not exist', async () => {
      mockPrisma.trailer.findUnique.mockImplementationOnce(() => Promise.resolve(null));

      await expect(
        service.generateUploadUrl({
          fileType: 'qc_photo',
          trailerId: 999,
          fileName: 'inspection.jpg',
        }),
      ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
    });
  });

  // =========================================================================
  // generateDownloadUrl
  // =========================================================================
  describe('generateDownloadUrl', () => {
    it('should generate a pre-signed download URL', async () => {
      const result = await service.generateDownloadUrl('qc/100/abc-def.jpg');

      expect(result.downloadUrl).toBe('https://spaces.example.com/signed-url');
      expect(result.storageKey).toBe('qc/100/abc-def.jpg');
      expect(result.expiresIn).toBe(900);
    });

    it('should accept delivery prefix', async () => {
      const result = await service.generateDownloadUrl('delivery/200/test.png');
      expect(result.storageKey).toBe('delivery/200/test.png');
    });

    it('should accept so-pdf prefix', async () => {
      const result = await service.generateDownloadUrl('so-pdf/300/doc.pdf');
      expect(result.storageKey).toBe('so-pdf/300/doc.pdf');
    });

    it('should accept damage prefix', async () => {
      const result = await service.generateDownloadUrl('damage/400/dmg.jpg');
      expect(result.storageKey).toBe('damage/400/dmg.jpg');
    });

    it('should throw for invalid prefix', async () => {
      await expect(service.generateDownloadUrl('hacker/evil.exe')).rejects.toThrow(
        'Invalid storage key prefix',
      );
    });
  });

  // =========================================================================
  // listObjects
  // =========================================================================
  describe('listObjects', () => {
    it('should return keys from S3 listing', async () => {
      const keys = await service.listObjects('qc/');
      expect(keys).toEqual(['qc/1/test.jpg']);
    });
  });

  // =========================================================================
  // VALID_FILE_TYPES export
  // =========================================================================
  it('should export exactly 4 valid file types', () => {
    expect(VALID_FILE_TYPES).toEqual([
      'qc_photo',
      'delivery_photo',
      'so_pdf',
      'damage_photo',
    ]);
  });
});
