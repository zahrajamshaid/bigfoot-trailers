// =============================================================================
// BIGFOOT TRAILERS — One-shot: correct the 6930 + 6681 loads (2026-08-04)
//
// Follow-up to fix-complete-single-pull-loads. The owner clarified:
//   - SO 6930 should be DELIVERED TO JAX (the Jacksonville yard), matching the
//     other Jax loads 6920/6860 that are already correct: the delivery records
//     a Jacksonville destination and the trailer sits at the Jax yard as
//     ready_for_delivery (delivered to a BF yard is stock, not terminal). The
//     earlier pass completed it with a null destination + trailer=delivered;
//     this repoints it to Jax.
//   - SO 6681 should be SOLD TO TROPIC. It's already delivered and sale=sold,
//     but "Tropic" was only free-text soldToName with no linked customer.
//     Attach the real Tropic Trailers customer record (id 6), the same way the
//     sibling Tropic loads (6774/6873/6829) carry it.
//
// Touches ONLY these two trailers. Audit-logged. Idempotent: re-running is a
// no-op once each field already matches.
// Run:  gh workflow run db-seed.yml -f script=fix-jax-tropic-load-corrections-2026-08-04
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const DRY_RUN = process.env['DRY_RUN'] === 'true';
const JAX_LOCATION_ID = 4; // JACKSONVILLE
const TROPIC_CUSTOMER_ID = 6n; // "Tropic Trailers"

async function main(): Promise<void> {
  console.log(`🔧 Correcting loads 6930 + 6681${DRY_RUN ? ' (DRY RUN — nothing written)' : ''}\n`);

  // ── SO 6930 → delivered to the Jacksonville yard ───────────────────────────
  {
    const trailer = await prisma.trailer.findFirst({
      where: { soNumber: '6930' },
      select: { id: true, status: true, currentLocationId: true },
    });
    const delivery = await prisma.delivery.findFirst({
      where: { deliveryType: 'single_pull', trailer: { soNumber: '6930' } },
      select: { id: true, status: true, destinationLocationId: true },
    });

    if (!trailer || !delivery) {
      console.log('  ⚠️  SO 6930: trailer or single_pull delivery not found — skipped.');
    } else {
      const deliveryNeedsDest = delivery.destinationLocationId !== JAX_LOCATION_ID;
      const trailerNeedsMove =
        trailer.status !== 'ready_for_delivery' || trailer.currentLocationId !== JAX_LOCATION_ID;

      if (!deliveryNeedsDest && !trailerNeedsMove) {
        console.log('  ✓ SO 6930: already delivered to Jacksonville — nothing to do.');
      } else {
        console.log(`  → SO 6930: delivery ${delivery.id} dest → JACKSONVILLE; ` +
          `trailer → ready_for_delivery @ JACKSONVILLE (was ${trailer.status}, loc ${trailer.currentLocationId})`);
        if (!DRY_RUN) {
          await prisma.$transaction(async (tx) => {
            if (deliveryNeedsDest) {
              await tx.delivery.update({
                where: { id: delivery.id },
                data: { destinationLocationId: JAX_LOCATION_ID, status: 'delivered' },
              });
            }
            if (trailerNeedsMove) {
              await tx.trailer.update({
                where: { id: trailer.id },
                data: { status: 'ready_for_delivery', currentLocationId: JAX_LOCATION_ID },
              });
            }
            await tx.auditLog.create({
              data: {
                entityType: 'trailer',
                entityId: trailer.id,
                action: 'delivery.destination_corrected',
                oldValues: {
                  deliveryDestination: delivery.destinationLocationId,
                  trailerStatus: trailer.status,
                  trailerLocationId: trailer.currentLocationId,
                },
                newValues: {
                  deliveryDestination: JAX_LOCATION_ID,
                  trailerStatus: 'ready_for_delivery',
                  trailerLocationId: JAX_LOCATION_ID,
                  note: "Owner: 6930 delivered to Jax — recorded the Jacksonville destination and landed the trailer at that yard",
                },
              },
            });
          });
        }
      }
    }
  }

  // ── SO 6681 → sold to Tropic (link the real customer) ──────────────────────
  {
    const trailer = await prisma.trailer.findFirst({
      where: { soNumber: '6681' },
      select: { id: true, status: true, saleStatus: true, customerId: true },
    });

    if (!trailer) {
      console.log('  ⚠️  SO 6681: not found — skipped.');
    } else if (trailer.customerId === TROPIC_CUSTOMER_ID && trailer.saleStatus === 'sold') {
      console.log('  ✓ SO 6681: already sold to Tropic Trailers — nothing to do.');
    } else {
      console.log(`  → SO 6681: customer → Tropic Trailers (id 6), sale → sold ` +
        `(was custId=${trailer.customerId ?? '-'}, sale=${trailer.saleStatus}); status ${trailer.status} kept`);
      if (!DRY_RUN) {
        await prisma.$transaction(async (tx) => {
          await tx.trailer.update({
            where: { id: trailer.id },
            data: { customerId: TROPIC_CUSTOMER_ID, saleStatus: 'sold' },
          });
          await tx.auditLog.create({
            data: {
              entityType: 'trailer',
              entityId: trailer.id,
              action: 'trailer.sold_to_customer',
              oldValues: { customerId: trailer.customerId != null ? Number(trailer.customerId) : null, saleStatus: trailer.saleStatus },
              newValues: {
                customerId: Number(TROPIC_CUSTOMER_ID),
                saleStatus: 'sold',
                note: 'Owner: 6681 sold to Tropic — linked the Tropic Trailers customer record (already delivered)',
              },
            },
          });
        });
      }
    }
  }

  console.log(`\n🎉 Done${DRY_RUN ? ' (dry run)' : ''}.`);
}

main()
  .catch((e) => {
    console.error('❌ Correction failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
