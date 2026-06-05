// =============================================================================
// BIGFOOT TRAILERS — One-shot: retag historical audit_logs entity_type rows
//
// The path parser in audit-log.interceptor.ts mislabelled multi-segment
// resources for as long as the interceptor has been live:
//
//   path                              before              after
//   ────────────────────────────────  ─────────────────   ────────────────────
//   POST /qc/inspections              qc                  qc_inspection
//   POST /qc/inspections/:id/...      inspection          qc_inspection
//   POST /qc/checklist-items          qc                  qc_checklist_item
//   PATCH /qc/checklist-items/:id     checklist_item      qc_checklist_item
//   POST /deliveries/batches          delivery            delivery_batch
//   PATCH /deliveries/batches/:id     batche              delivery_batch
//   POST /deliveries/batches/:id/...  batche              delivery_batch
//
// The parser fix in this commit lands new entries correctly; this script
// retags everything written before the fix so the mobile audit-log dropdown
// (which filters by exact entity_type strings: qc_inspection, delivery,
// etc.) actually surfaces historical QC submissions and batch edits.
//
// Mapping rules:
//   • Plain `qc` is ambiguous — it could be a QC inspection submission or
//     a checklist-items mutation. Heuristic: if there's a same-action
//     QcInspection row created near the audit_log createdAt, retag as
//     `qc_inspection`. Otherwise retag as `qc_checklist_item`. Both are
//     valid surfaces in the mobile dropdown.
//   • Plain `inspection` → `qc_inspection`.
//   • Plain `checklist_item` → `qc_checklist_item`.
//   • Plain `batche` → `delivery_batch`.
//
// Idempotent: a second run is a no-op once everything is retagged.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const NEAR_INSPECTION_WINDOW_MS = 60_000; // 1-minute tolerance per row

async function main(): Promise<void> {
  console.log('🔁 Retagging historical audit_logs entity_type values\n');

  // ─── 1. Straightforward 1-to-1 retags ─────────────────────────────────
  const straightforward: Array<[string, string]> = [
    ['inspection', 'qc_inspection'],
    ['checklist_item', 'qc_checklist_item'],
    ['batche', 'delivery_batch'],
  ];

  for (const [from, to] of straightforward) {
    const res = await prisma.auditLog.updateMany({
      where: { entityType: from },
      data: { entityType: to },
    });
    console.log(`  ${from.padEnd(18)} → ${to.padEnd(20)} (${res.count} rows)`);
  }

  // ─── 2. Disambiguate `qc` rows ────────────────────────────────────────
  // Need to look at each row and decide qc_inspection vs qc_checklist_item.
  // We do this by joining the audit_log row's createdAt + entityId against
  // the QcInspection table — if a QcInspection with that id exists, the row
  // was a /qc/inspections write. Otherwise it was a checklist-items write
  // (since /qc/checklist-items[/:id] is the other write surface that
  // mislabels as `qc`).
  const ambiguous = await prisma.auditLog.findMany({
    where: { entityType: 'qc' },
    select: { id: true, entityId: true, createdAt: true },
    orderBy: { id: 'asc' },
  });
  console.log(`\n📋 Disambiguating ${ambiguous.length} rows at entity_type='qc'\n`);

  let toInspection = 0;
  let toChecklistItem = 0;
  for (const row of ambiguous) {
    const insp = await prisma.qcInspection.findUnique({
      where: { id: row.entityId },
      select: { id: true, inspectedAt: true },
    });

    // Same id AND inspected within the tolerance window → it's a QcInspection.
    const isInspection =
      insp !== null &&
      Math.abs(insp.inspectedAt.getTime() - row.createdAt.getTime()) <
        NEAR_INSPECTION_WINDOW_MS;

    const target = isInspection ? 'qc_inspection' : 'qc_checklist_item';
    await prisma.auditLog.update({
      where: { id: row.id },
      data: { entityType: target },
    });
    if (isInspection) toInspection++;
    else toChecklistItem++;
  }

  console.log(`  → qc_inspection     (${toInspection} rows)`);
  console.log(`  → qc_checklist_item (${toChecklistItem} rows)`);
  console.log(`\n🎉 Done.`);
}

main()
  .catch((e) => {
    console.error('❌ Retag failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
