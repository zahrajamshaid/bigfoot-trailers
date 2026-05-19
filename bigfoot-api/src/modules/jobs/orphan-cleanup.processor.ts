import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';

/**
 * Orphan Cleanup Processor
 *
 * Runs daily to find storage objects that are not referenced by any
 * QcPhoto, DeliveryPhoto, or Trailer (qbSoPdfStorageKey) record.
 * Deletes orphaned files from DigitalOcean Spaces.
 */
@Injectable()
export class OrphanCleanupProcessor implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(OrphanCleanupProcessor.name);
  private intervalRef: ReturnType<typeof setInterval> | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly storageService: StorageService,
  ) {}

  onModuleInit() {
    // Run once a day (24 hours)
    this.intervalRef = setInterval(() => this.cleanup(), 24 * 60 * 60_000);
    this.logger.log('Orphan cleanup processor started (24h interval)');
  }

  onModuleDestroy() {
    if (this.intervalRef) {
      clearInterval(this.intervalRef);
      this.intervalRef = null;
    }
  }

  async cleanup(): Promise<number> {
    let deleted = 0;

    try {
      const prefixes = ['qc', 'delivery', 'so-pdf', 'damage'];

      for (const prefix of prefixes) {
        const objectKeys = await this.storageService.listObjects(`${prefix}/`);

        if (objectKeys.length === 0) continue;

        // Collect all referenced keys from the database for this prefix
        const referencedKeys = new Set<string>();

        if (prefix === 'qc') {
          const photos = await this.prisma.qcPhoto.findMany({
            where: { storageKey: { in: objectKeys } },
            select: { storageKey: true },
          });
          photos.forEach((p) => referencedKeys.add(p.storageKey));
        } else if (prefix === 'delivery' || prefix === 'damage') {
          const photos = await this.prisma.deliveryPhoto.findMany({
            where: { storageKey: { in: objectKeys } },
            select: { storageKey: true },
          });
          photos.forEach((p) => referencedKeys.add(p.storageKey));
        } else if (prefix === 'so-pdf') {
          const trailers = await this.prisma.trailer.findMany({
            where: { qbSoPdfStorageKey: { in: objectKeys } },
            select: { qbSoPdfStorageKey: true },
          });
          trailers.forEach((t) => {
            if (t.qbSoPdfStorageKey) referencedKeys.add(t.qbSoPdfStorageKey);
          });
        }

        // Delete orphaned objects (in storage but not in DB)
        for (const key of objectKeys) {
          if (!referencedKeys.has(key)) {
            try {
              await this.storageService.deleteObject(key);
              deleted++;
              this.logger.log(`Deleted orphaned file: ${key}`);
            } catch (err) {
              this.logger.error(
                `Failed to delete orphan ${key}: ${(err as Error)?.message}`,
              );
            }
          }
        }
      }

      if (deleted > 0) {
        this.logger.log(`Orphan cleanup complete: ${deleted} files deleted`);
      }
    } catch (err) {
      this.logger.error(`Orphan cleanup failed: ${(err as Error)?.message}`);
    }

    return deleted;
  }
}
