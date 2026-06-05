// =============================================================================
// BIGFOOT TRAILERS — One-shot: Mulberry open-stock cleanup + SO 6567 → VA
//
// 1) Mulberry open-stock cleanup (7 trailers):
//      6791, 6788, 6831, 6717, 6797, 6772, 6568
//
//    These were leaking into the "Ready" trailer list even though they are
//    open stock at Mulberry with no customer attached. The new
//    trailers.service filter (`status=ready_for_delivery` excludes Mulberry
//    stock-builds with no customer) hides them automatically; this script
//    just normalises their record so the inventory state is unambiguous:
//      • isStockBuild = true
//      • currentLocationId = MULBERRY
//      • saleStatus = available
//      • customerId = null AND soldToName = null
//
// 2) SO 6567 → Virginia (Tappahannock):
//      • currentLocationId = TAPPAHANNOCK
//      • isStockBuild = true
//      • saleStatus + customer fields untouched (the user explicitly asked
//        to leave them as-is).
//
// Strict guard rails:
//   • If a trailer has any open delivery (status scheduled or in_transit),
//     skip it — relocating a trailer mid-shipment would silently desync
//     the delivery row and the driver's queue.
//   • Each row's "before" state is logged so the run output reads as an
//     audit trail.
//
// Idempotent: re-runs after the first pass are no-ops because every field
// is set to the canonical target value.
// =============================================================================

import 'dotenv/config';
import { DeliveryStatus, TrailerSaleStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const MULBERRY_OPEN_STOCK_SO_NUMBERS = [
  '6791',
  '6788',
  '6831',
  '6717',
  '6797',
  '6772',
  '6568',
];
const SIX567 = '6567';

async function loadLocations(): Promise<Map<string, number>> {
  const rows = await prisma.location.findMany({
    where: { code: { in: ['MULBERRY', 'TAPPAHANNOCK'] } },
    select: { id: true, code: true },
  });
  const byCode = new Map(rows.map((r) => [r.code, r.id]));
  for (const code of ['MULBERRY', 'TAPPAHANNOCK']) {
    if (!byCode.has(code)) {
      throw new Error(`Location ${code} not found — run the base seed first.`);
    }
  }
  return byCode;
}

async function hasOpenDelivery(trailerId: bigint): Promise<boolean> {
  const open = await prisma.delivery.count({
    where: {
      trailerId,
      status: { in: [DeliveryStatus.scheduled, DeliveryStatus.in_transit] },
    },
  });
  return open > 0;
}

async function main(): Promise<void> {
  console.log('🧹 Normalising Mulberry open-stock + relocating SO 6567 to VA\n');

  const locByCode = await loadLocations();
  const mulberryId = locByCode.get('MULBERRY')!;
  const tappahannockId = locByCode.get('TAPPAHANNOCK')!;

  // ─── 1) Mulberry open-stock cleanup ────────────────────────────────────
  console.log(`📋 Cleaning ${MULBERRY_OPEN_STOCK_SO_NUMBERS.length} Mulberry open-stock trailer(s):\n`);

  let stockCleaned = 0;
  let stockSkipped = 0;

  for (const so of MULBERRY_OPEN_STOCK_SO_NUMBERS) {
    const trailer = await prisma.trailer.findUnique({
      where: { soNumber: so },
      select: {
        id: true,
        soNumber: true,
        currentLocationId: true,
        isStockBuild: true,
        saleStatus: true,
        customerId: true,
        soldToName: true,
        currentLocation: { select: { code: true } },
      },
    });
    if (!trailer) {
      console.log(`  ${so.padEnd(6)} → not found, skipping`);
      stockSkipped++;
      continue;
    }
    if (await hasOpenDelivery(trailer.id)) {
      console.log(
        `  ${so.padEnd(6)} → has an open delivery, skipping (would desync routing)`,
      );
      stockSkipped++;
      continue;
    }

    console.log(
      `  ${so.padEnd(6)} before → location=${trailer.currentLocation?.code ?? trailer.currentLocationId}, stock=${trailer.isStockBuild}, sale=${trailer.saleStatus}, customerId=${trailer.customerId ?? 'null'}, soldToName=${trailer.soldToName ?? 'null'}`,
    );

    await prisma.trailer.update({
      where: { id: trailer.id },
      data: {
        isStockBuild: true,
        currentLocationId: mulberryId,
        saleStatus: TrailerSaleStatus.available,
        customerId: null,
        soldToName: null,
      },
    });
    stockCleaned++;
    console.log(
      `  ${so.padEnd(6)} after  → location=MULBERRY, stock=true, sale=available, customer=null`,
    );
  }

  // ─── 2) SO 6567 → Virginia ─────────────────────────────────────────────
  console.log(`\n🚚 Relocating SO ${SIX567} → Virginia (Tappahannock):\n`);

  let six567Touched = false;
  const six567 = await prisma.trailer.findUnique({
    where: { soNumber: SIX567 },
    select: {
      id: true,
      soNumber: true,
      currentLocationId: true,
      isStockBuild: true,
      saleStatus: true,
      customerId: true,
      soldToName: true,
      currentLocation: { select: { code: true } },
    },
  });
  if (!six567) {
    console.log(`  ${SIX567} → not found, skipping`);
  } else if (await hasOpenDelivery(six567.id)) {
    console.log(
      `  ${SIX567} → has an open delivery, skipping (would desync routing)`,
    );
  } else if (
    six567.currentLocationId === tappahannockId &&
    six567.isStockBuild === true
  ) {
    console.log(`  ${SIX567} → already at TAPPAHANNOCK as stock, no change`);
  } else {
    console.log(
      `  ${SIX567} before → location=${six567.currentLocation?.code ?? six567.currentLocationId}, stock=${six567.isStockBuild}`,
    );
    await prisma.trailer.update({
      where: { id: six567.id },
      data: {
        currentLocationId: tappahannockId,
        isStockBuild: true,
      },
    });
    six567Touched = true;
    console.log(`  ${SIX567} after  → location=TAPPAHANNOCK, stock=true`);
  }

  console.log(
    `\n🎉 Done. ${stockCleaned} Mulberry trailer(s) normalised, ${stockSkipped} skipped, SO 6567 ${six567Touched ? 'moved to VA' : 'unchanged'}.`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Cleanup failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
