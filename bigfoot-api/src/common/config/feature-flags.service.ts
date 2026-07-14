import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * Phase 2 feature flags.
 *
 * Every Phase 2 capability (QuickBooks sync, the Sales-Order configurator,
 * BOM authoring) ships dark and stays inert in production until its flag is
 * flipped on. This lets us merge and deploy each slice without disturbing the
 * live shop-floor operation.
 *
 * All flags default to FALSE — a missing env var means "off". The master
 * `PHASE2_ENABLED` gates the whole program; the per-capability flags gate
 * individual surfaces so we can enable them one at a time during the pilot.
 */
export enum FeatureFlag {
  /** Master kill-switch for the entire Phase 2 program. */
  PHASE2 = 'PHASE2_ENABLED',
  /** QuickBooks Online sync (OAuth, push, webhooks, reconciliation). */
  QBO_SYNC = 'QBO_SYNC_ENABLED',
  /** App-native Sales Orders + configurator + Quick Estimate. */
  SALES_ORDERS = 'SALES_ORDERS_ENABLED',
  /** Shop BOM authoring + ResolvedBOM generation. */
  BOM = 'BOM_ENABLED',
}

@Injectable()
export class FeatureFlagsService {
  private readonly logger = new Logger('FeatureFlags');

  constructor(private readonly config: ConfigService) {}

  /**
   * True only when the flag's env var is exactly "true". Anything else
   * (missing, "false", "0", "yes", …) reads as off — we don't guess.
   *
   * A capability flag is additionally gated by the master PHASE2 flag: a
   * sub-flag can never be "on" while the whole program is off, so flipping
   * PHASE2 off is a single-switch emergency stop for everything.
   */
  isEnabled(flag: FeatureFlag): boolean {
    const raw = this.config.get<string>(flag);
    const on = raw === 'true';
    if (flag === FeatureFlag.PHASE2) return on;
    return on && this.isEnabled(FeatureFlag.PHASE2);
  }

  /** Throws SERVICE_UNAVAILABLE-shaped guard helper for services. */
  assertEnabled(flag: FeatureFlag): void {
    if (!this.isEnabled(flag)) {
      this.logger.warn(`Blocked call to a disabled feature: ${flag}`);
      // Kept as a plain Error here to avoid a common→errors import cycle;
      // controllers/services that want the typed 503 throw AppError directly.
      throw new Error(`Feature "${flag}" is not enabled`);
    }
  }
}
