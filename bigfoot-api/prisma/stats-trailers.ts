// =============================================================================
// BIGFOOT TRAILERS — Read-only trailer tally
//
// Counts trailers across the lifecycle. "In stock inventory" is the same
// query used by the mobile Stock Inventory screen: the latest delivered
// Delivery per trailer (distinct on trailerId, orderBy deliveredAt desc).
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=stats-trailers
// =============================================================================

import 'dotenv/config';
import { DeliveryStatus, TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  const total = await prisma.trailer.count();

  // Status breakdown
  const byStatus = await prisma.trailer.groupBy({
    by: ['status'],
    _count: { _all: true },
  });
  const statusMap: Record<string, number> = {};
  for (const r of byStatus) statusMap[r.status] = r._count._all;

  const production =
    (statusMap[TrailerStatus.pending_production] ?? 0) +
    (statusMap[TrailerStatus.in_production] ?? 0);
  const readyForDelivery = statusMap[TrailerStatus.ready_for_delivery] ?? 0;
  const inTransit = statusMap[TrailerStatus.in_transit] ?? 0;
  const delivered = statusMap[TrailerStatus.delivered] ?? 0;
  const onHold = statusMap[TrailerStatus.on_hold] ?? 0;

  console.log('═════ TRAILER LIFECYCLE ═════');
  console.log(`  TOTAL:                ${total}`);
  console.log(`  pending_production:   ${statusMap[TrailerStatus.pending_production] ?? 0}`);
  console.log(`  in_production:        ${statusMap[TrailerStatus.in_production] ?? 0}`);
  console.log(`  → production total:   ${production}`);
  console.log(`  ready_for_delivery:   ${readyForDelivery}`);
  console.log(`  in_transit:           ${inTransit}`);
  console.log(`  delivered:            ${delivered}`);
  console.log(`  on_hold:              ${onHold}`);

  // Stock inventory — driven by the latest delivered Delivery per trailer
  // (same logic as DeliveriesService.getStockInventory). We pull all
  // delivered Deliveries with a destination Location, dedupe per trailer
  // keeping the most recent, then group by location.
  const delivered_deliveries = await prisma.delivery.findMany({
    where: {
      status: DeliveryStatus.delivered,
      destinationLocationId: { not: null },
    },
    orderBy: { deliveredAt: 'desc' },
    select: {
      trailerId: true,
      destinationLocationId: true,
      destinationLocation: { select: { code: true, name: true } },
      trailer: {
        select: {
          status: true,
          saleStatus: true,
          isStockBuild: true,
          trailerModel: { select: { code: true, series: true } },
        },
      },
    },
  });

  // Dedupe by trailer (first encountered = latest by deliveredAt desc).
  const seen = new Set<bigint>();
  const latestPerTrailer = delivered_deliveries.filter((d) => {
    if (seen.has(d.trailerId)) return false;
    seen.add(d.trailerId);
    return true;
  });

  // Filter to trailers that haven't moved on — exclude those with newer
  // live deliveries (scheduled / in_transit) that would supersede the
  // landed Delivery. For a quick count we treat trailers as "in stock" if
  // their status is one of: delivered, ready_for_delivery, on_hold.
  const stockStatuses: TrailerStatus[] = [
    TrailerStatus.delivered,
    TrailerStatus.ready_for_delivery,
    TrailerStatus.on_hold,
  ];
  const inStock = latestPerTrailer.filter((d) =>
    stockStatuses.includes(d.trailer.status),
  );

  // Group by destination location.
  const byLoc = new Map<string, { name: string; count: number }>();
  for (const d of inStock) {
    const code = d.destinationLocation!.code;
    const name = d.destinationLocation!.name;
    const cur = byLoc.get(code) ?? { name, count: 0 };
    cur.count++;
    byLoc.set(code, cur);
  }

  console.log('\n═════ STOCK INVENTORY (by yard) ═════');
  console.log(`  TOTAL in stock:       ${inStock.length}`);
  for (const [code, info] of [...byLoc.entries()].sort()) {
    console.log(`    ${code.padEnd(15)} ${info.name.padEnd(35)} ${info.count}`);
  }

  // Sale-status breakdown of the in-stock pool.
  const stockBySale: Record<string, number> = {};
  for (const d of inStock) {
    const k = d.trailer.saleStatus;
    stockBySale[k] = (stockBySale[k] ?? 0) + 1;
  }
  console.log('\n═════ STOCK INVENTORY (by sale status) ═════');
  for (const [k, v] of Object.entries(stockBySale).sort()) {
    console.log(`    ${k.padEnd(15)} ${v}`);
  }

  // Series breakdown of the in-stock pool.
  const stockBySeries: Record<string, number> = {};
  for (const d of inStock) {
    const k = d.trailer.trailerModel.series;
    stockBySeries[k] = (stockBySeries[k] ?? 0) + 1;
  }
  console.log('\n═════ STOCK INVENTORY (by series) ═════');
  for (const [k, v] of Object.entries(stockBySeries).sort()) {
    console.log(`    ${k.padEnd(20)} ${v}`);
  }

  // Production breakdown by series.
  const prodTrailers = await prisma.trailer.findMany({
    where: {
      status: {
        in: [TrailerStatus.pending_production, TrailerStatus.in_production],
      },
    },
    select: { trailerModel: { select: { series: true } } },
  });
  const prodBySeries: Record<string, number> = {};
  for (const t of prodTrailers) {
    const k = t.trailerModel.series;
    prodBySeries[k] = (prodBySeries[k] ?? 0) + 1;
  }
  console.log('\n═════ IN PRODUCTION (by series) ═════');
  console.log(`  TOTAL in production:  ${prodTrailers.length}`);
  for (const [k, v] of Object.entries(prodBySeries).sort()) {
    console.log(`    ${k.padEnd(20)} ${v}`);
  }
}

main()
  .catch((e) => {
    console.error('❌ stats failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
