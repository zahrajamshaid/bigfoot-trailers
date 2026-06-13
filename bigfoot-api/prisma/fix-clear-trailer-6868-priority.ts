// =============================================================================
// BIGFOOT TRAILERS — One-shot: clear SO 6868's explicit global priority
//
// SO 6868 has an explicit global_priority = 1 set on the trailer record,
// which was outranking older trailers in PAINT_B (6787 has been sitting
// longer but defaulted to the 9999 priority, so the explicit-priority tier
// puts 6868 first). The user wants 6868 to fall back to the oldest-first
// tier alongside everyone else, so we flip global_priority back to the
// 9999 default. The original setter is unknown — likely an old manual
// adjustment that was never cleared.
//
// Logs the before/after on stdout. Idempotent — re-running after the flip
// is a no-op.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const TARGET_SO = '6868';
const DEFAULT_PRIORITY = 9999;

async function main(): Promise<void> {
  const trailer = await prisma.trailer.findUnique({
    where: { soNumber: TARGET_SO },
    select: { id: true, soNumber: true, globalPriority: true, isHot: true },
  });
  if (!trailer) throw new Error(`Trailer SO ${TARGET_SO} not found.`);

  console.log(
    `📋 SO ${trailer.soNumber} — before: globalPriority=${trailer.globalPriority}, isHot=${trailer.isHot}`,
  );

  if (trailer.globalPriority === DEFAULT_PRIORITY) {
    console.log('  Already at default — no change.');
    return;
  }

  await prisma.trailer.update({
    where: { id: trailer.id },
    data: { globalPriority: DEFAULT_PRIORITY },
  });

  console.log(
    `  ✅ globalPriority: ${trailer.globalPriority} → ${DEFAULT_PRIORITY}`,
  );
  console.log(
    `\n🎉 Done. 6868 will now sort by age in PAINT_B like everyone else.`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Fix failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
