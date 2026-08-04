// =============================================================================
// BIGFOOT TRAILERS — One-shot: finish the stuck "single pull" loads (2026-08-04)
//
// From the owner's load sheet. Three single_pull deliveries were entered but
// never completed ("Single pull" note on the pad). Two need completing, one is
// a leftover duplicate that needs removing. Everything else on the sheet was
// already delivered or explicitly excluded (verified against prod first).
//
//   COMPLETE (mark delivered), mirroring deliveries.service.markComplete:
//     - SO 6930  single_pull → sold to Jax, hauled out
//     - SO 6681  single_pull → sold to Tropic, hauled out
//   Both have a null destination_location_id, so — exactly like markComplete's
//   null-destination branch — the delivery goes to `delivered` and the trailer
//   becomes `delivered` (a customer haul is terminal).
//
//   DELETE (remove the duplicate):
//     - SO 6829  already delivered via batch 16 (stack_to_dealer). It carries a
//       stray single_pull still in `scheduled`. We drop that row + its
//       dependents but DELIBERATELY LEAVE the trailer `delivered` — the app's
//       generic delivery-delete would wrongly revert it to ready_for_delivery
//       because 6829's remaining delivered row has no destination location.
//
// Each target is matched by (soNumber, delivery_type=single_pull,
// status=scheduled) so it hits exactly the right rows and is safe to re-run.
// Every change writes an audit_log row.
//
// Idempotent: once completed/removed there's nothing left to match.
// Run:  gh workflow run db-seed.yml -f script=fix-complete-single-pull-loads-2026-08-04
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const DRY_RUN = process.env['DRY_RUN'] === 'true';

const COMPLETE_SOS = ['6930', '6681'];
const DELETE_DUP_SOS = ['6829'];

async function findStuckSinglePull(so: string) {
  return prisma.delivery.findFirst({
    where: {
      status: 'scheduled',
      deliveryType: 'single_pull',
      trailer: { soNumber: so },
    },
    select: {
      id: true,
      destinationLocationId: true,
      deliveryBatchId: true,
      trailerId: true,
      trailer: { select: { soNumber: true, status: true } },
    },
  });
}

async function main(): Promise<void> {
  console.log(`🚚 Finishing stuck single-pull loads${DRY_RUN ? ' (DRY RUN — nothing written)' : ''}\n`);

  // ── Complete: 6930, 6681 ───────────────────────────────────────────────────
  for (const so of COMPLETE_SOS) {
    const d = await findStuckSinglePull(so);
    if (!d) {
      console.log(`  ✓ SO ${so}: no scheduled single_pull found — already completed, skipping.`);
      continue;
    }
    // Mirror markComplete: null destination → trailer delivered; a destination
    // (BF yard) → ready_for_delivery + move location. These two are null-dest.
    const trailerTerminal = d.destinationLocationId == null;
    console.log(`  → SO ${so}: complete delivery ${d.id} → delivered` +
      `; trailer → ${trailerTerminal ? 'delivered' : 'ready_for_delivery (moved)'}`);
    if (DRY_RUN) continue;

    await prisma.$transaction(async (tx) => {
      await tx.delivery.update({
        where: { id: d.id },
        data: { status: 'delivered', deliveredAt: new Date() },
      });

      if (d.destinationLocationId != null) {
        await tx.trailer.update({
          where: { id: d.trailerId },
          data: { status: 'ready_for_delivery', currentLocationId: d.destinationLocationId },
        });
      } else {
        await tx.trailer.update({
          where: { id: d.trailerId },
          data: { status: 'delivered' },
        });
      }

      await tx.auditLog.create({
        data: {
          entityType: 'trailer',
          entityId: d.trailerId,
          action: 'delivery.completed',
          oldValues: { deliveryId: Number(d.id), deliveryStatus: 'scheduled', trailerStatus: d.trailer.status },
          newValues: {
            deliveryStatus: 'delivered',
            trailerStatus: trailerTerminal ? 'delivered' : 'ready_for_delivery',
            note: "Stuck single_pull load completed from the owner's load sheet",
          },
        },
      });
    });
  }

  // ── Delete duplicate: 6829 (leave trailer delivered) ───────────────────────
  for (const so of DELETE_DUP_SOS) {
    const d = await findStuckSinglePull(so);
    if (!d) {
      console.log(`  ✓ SO ${so}: no stray scheduled single_pull found — already cleaned, skipping.`);
      continue;
    }
    console.log(`  → SO ${so}: delete duplicate scheduled single_pull ${d.id} ` +
      `(trailer stays ${d.trailer.status})`);
    if (DRY_RUN) continue;

    await prisma.$transaction(async (tx) => {
      await tx.deliveryPhoto.deleteMany({ where: { deliveryId: d.id } });
      await tx.locationReceipt.deleteMany({ where: { deliveryId: d.id } });
      await tx.smsLog.updateMany({ where: { deliveryId: d.id }, data: { deliveryId: null } });
      await tx.delivery.delete({ where: { id: d.id } });
      // Intentionally NOT touching the trailer — 6829 is already delivered via
      // its batch-16 stack_to_dealer row; this only removes a duplicate.

      await tx.auditLog.create({
        data: {
          entityType: 'trailer',
          entityId: d.trailerId,
          action: 'delivery.duplicate_removed',
          oldValues: { deliveryId: Number(d.id), deliveryType: 'single_pull', deliveryStatus: 'scheduled' },
          newValues: {
            trailerStatus: d.trailer.status,
            note: 'Removed a leftover scheduled single_pull duplicate; trailer already delivered via batch 16',
          },
        },
      });
    });
  }

  console.log(`\n🎉 Done${DRY_RUN ? ' (dry run)' : ''}.`);
}

main()
  .catch((e) => {
    console.error('❌ Load completion failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
