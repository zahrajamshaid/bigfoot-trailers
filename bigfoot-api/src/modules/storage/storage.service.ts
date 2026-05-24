import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { AppError, ErrorCode } from '../../common/errors';
import { ConfigService } from '@nestjs/config';
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
  ListObjectsV2Command,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { randomUUID } from 'crypto';
import { PrismaService } from '../../prisma/prisma.service';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

export const VALID_FILE_TYPES = [
  'qc_photo',
  'delivery_photo',
  'so_pdf',
  'damage_photo',
] as const;

export type FileType = (typeof VALID_FILE_TYPES)[number];

const FILE_TYPE_PREFIXES: Record<FileType, string> = {
  qc_photo: 'qc',
  delivery_photo: 'delivery',
  so_pdf: 'so-pdf',
  damage_photo: 'damage',
};

const PHOTO_EXTENSIONS = ['jpg', 'jpeg', 'png', 'webp'];
const PDF_EXTENSIONS = ['pdf'];
const ALL_EXTENSIONS = [...PHOTO_EXTENSIONS, ...PDF_EXTENSIONS];

const EXTENSION_CONTENT_TYPES: Record<string, string> = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  pdf: 'application/pdf',
};

/** Photo max: 10 MB, PDF max: 25 MB */
const MAX_SIZE_BYTES: Record<string, number> = {
  jpg: 10 * 1024 * 1024,
  jpeg: 10 * 1024 * 1024,
  png: 10 * 1024 * 1024,
  webp: 10 * 1024 * 1024,
  pdf: 25 * 1024 * 1024,
};

/** Pre-signed URL expiry: 15 minutes */
const PRESIGN_EXPIRY_SECONDS = 15 * 60;

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

@Injectable()
export class StorageService implements OnModuleInit {
  private readonly logger = new Logger(StorageService.name);
  private s3!: S3Client;
  private bucket!: string;
  private cdnBaseUrl!: string;

  constructor(
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  onModuleInit() {
    const endpoint = this.configService.get<string>('DO_SPACES_ENDPOINT');
    const region = this.configService.get<string>('DO_SPACES_REGION', 'us-east-1');
    const accessKeyId = this.configService.get<string>('DO_SPACES_ACCESS_KEY');
    const secretAccessKey = this.configService.get<string>('DO_SPACES_SECRET_KEY');
    this.bucket = this.configService.get<string>('DO_SPACES_BUCKET', 'bigfoot-storage');
    this.cdnBaseUrl = this.configService.get<string>('DO_SPACES_CDN_URL', '');

    if (endpoint && accessKeyId && secretAccessKey) {
      this.s3 = new S3Client({
        endpoint,
        region,
        credentials: { accessKeyId, secretAccessKey },
        forcePathStyle: false,
      });
      this.logger.log(`S3 client initialised — bucket: ${this.bucket}`);
    } else {
      // Create a stub client so the service can be injected in tests/dev
      this.s3 = new S3Client({ region: 'us-east-1' });
      this.logger.warn(
        'DO Spaces credentials not configured — storage operations will fail',
      );
    }
  }

  // -------------------------------------------------------------------------
  // POST /storage/presign — generate pre-signed upload URL
  // -------------------------------------------------------------------------
  async generateUploadUrl(params: {
    fileType: string;
    trailerId: number;
    fileName: string;
  }): Promise<{
    uploadUrl: string;
    storageKey: string;
    expiresIn: number;
    maxSizeBytes: number;
    contentType: string;
  }> {
    // 1. Validate file_type
    if (!VALID_FILE_TYPES.includes(params.fileType as FileType)) {
      throw new AppError(
        ErrorCode.PRESIGN_INVALID_FILE_TYPE,
        `Invalid file_type "${params.fileType}". Allowed: ${VALID_FILE_TYPES.join(', ')}`,
      );
    }
    const fileType = params.fileType as FileType;

    // 2. Validate extension
    const ext = this.extractExtension(params.fileName);
    if (!ext || !ALL_EXTENSIONS.includes(ext)) {
      throw new AppError(
        ErrorCode.PRESIGN_INVALID_FILE_TYPE,
        `Invalid file extension ".${ext ?? '(none)'}". Allowed: ${ALL_EXTENSIONS.join(', ')}`,
      );
    }

    // 3. Validate extension matches file type
    if (fileType === 'so_pdf' && !PDF_EXTENSIONS.includes(ext)) {
      throw new AppError(
        ErrorCode.PRESIGN_INVALID_FILE_TYPE,
        `File type "so_pdf" requires a PDF extension. Got ".${ext}"`,
      );
    }
    if (fileType !== 'so_pdf' && !PHOTO_EXTENSIONS.includes(ext)) {
      throw new AppError(
        ErrorCode.PRESIGN_INVALID_FILE_TYPE,
        `File type "${fileType}" requires a photo extension (${PHOTO_EXTENSIONS.join(', ')}). Got ".${ext}"`,
      );
    }

    // 4. Look up the trailer's SO number — storage path is organised by SO
    //    so a sales order's files cluster together regardless of internal
    //    trailer id (which is opaque to operators).
    const trailer = await this.prisma.trailer.findUnique({
      where: { id: BigInt(params.trailerId) },
      select: { soNumber: true },
    });
    if (!trailer) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Trailer with id ${params.trailerId} not found`,
      );
    }
    // Defensive sanitisation — schema enforces SO format but a stray space
    // or slash would break S3 path semantics.
    const soSlug = trailer.soNumber.replace(/[^A-Za-z0-9._-]/g, '_');

    // 5. Build storage key
    const prefix = FILE_TYPE_PREFIXES[fileType];
    const uuid = randomUUID();
    const storageKey = `${prefix}/${soSlug}/${uuid}.${ext}`;

    // 5. Content type + size limit
    const contentType = EXTENSION_CONTENT_TYPES[ext]!;
    const maxSizeBytes = MAX_SIZE_BYTES[ext]!;

    // 6. Generate pre-signed PUT URL
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: storageKey,
      ContentType: contentType,
    });

    const uploadUrl = await getSignedUrl(this.s3, command, {
      expiresIn: PRESIGN_EXPIRY_SECONDS,
    });

    return {
      uploadUrl,
      storageKey,
      expiresIn: PRESIGN_EXPIRY_SECONDS,
      maxSizeBytes,
      contentType,
    };
  }

  // -------------------------------------------------------------------------
  // GET /storage/presign/:key — generate pre-signed download URL
  // -------------------------------------------------------------------------
  async generateDownloadUrl(storageKey: string): Promise<{
    downloadUrl: string;
    storageKey: string;
    expiresIn: number;
  }> {
    // Validate the key has a valid prefix
    const validPrefixes = Object.values(FILE_TYPE_PREFIXES);
    const keyPrefix = storageKey.split('/')[0];
    if (!validPrefixes.includes(keyPrefix!)) {
      throw new AppError(
        ErrorCode.PRESIGN_INVALID_FILE_TYPE,
        `Invalid storage key prefix "${keyPrefix}"`,
      );
    }

    const command = new GetObjectCommand({
      Bucket: this.bucket,
      Key: storageKey,
    });

    const downloadUrl = await getSignedUrl(this.s3, command, {
      expiresIn: PRESIGN_EXPIRY_SECONDS,
    });

    return {
      downloadUrl,
      storageKey,
      expiresIn: PRESIGN_EXPIRY_SECONDS,
    };
  }

  // -------------------------------------------------------------------------
  // Delete a single object — used by orphan cleanup
  // -------------------------------------------------------------------------
  async deleteObject(storageKey: string): Promise<void> {
    await this.s3.send(
      new DeleteObjectCommand({
        Bucket: this.bucket,
        Key: storageKey,
      }),
    );
  }

  // -------------------------------------------------------------------------
  // Best-effort batch deletion — called inline after a DB delete to clean up
  // Spaces immediately instead of waiting up to 24h for orphan-cleanup.
  // Individual failures are logged but not thrown; orphan-cleanup catches
  // anything that slips through, so a transient S3 outage doesn't roll back
  // the user's delete.
  // -------------------------------------------------------------------------
  async deleteObjects(storageKeys: string[]): Promise<void> {
    if (storageKeys.length === 0) return;
    const results = await Promise.allSettled(
      storageKeys.map((key) =>
        this.s3.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key })),
      ),
    );
    results.forEach((result, idx) => {
      if (result.status === 'rejected') {
        this.logger.warn(
          `Failed to delete ${storageKeys[idx]} from Spaces (orphan-cleanup will retry): ${
            (result.reason as Error)?.message
          }`,
        );
      }
    });
  }

  // -------------------------------------------------------------------------
  // List objects with a prefix — used by orphan cleanup
  // -------------------------------------------------------------------------
  async listObjects(prefix: string, maxKeys = 1000): Promise<string[]> {
    const result = await this.s3.send(
      new ListObjectsV2Command({
        Bucket: this.bucket,
        Prefix: prefix,
        MaxKeys: maxKeys,
      }),
    );

    return (result.Contents ?? [])
      .map((obj) => obj.Key)
      .filter((key): key is string => key != null);
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  private extractExtension(fileName: string): string | null {
    const parts = fileName.split('.');
    if (parts.length < 2) return null;
    return parts[parts.length - 1]!.toLowerCase();
  }
}
