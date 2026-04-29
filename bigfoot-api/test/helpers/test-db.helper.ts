/**
 * E2E Database Helpers — seed reference data & clean up transactional data.
 *
 * Reference tables (locations, departments, trailer_models, workflow_templates,
 * customers) are preserved across tests. All transactional data is wiped.
 */
import { PrismaService } from '../../src/prisma/prisma.service';

// ── Location seed data ──────────────────────────────────────────────────────

const LOCATIONS = [
  { code: 'MULBERRY', name: 'Bigfoot Trailers Mulberry', city: 'Mulberry', state: 'FL', isFactory: true },
  { code: 'JACKSONVILLE', name: 'Bigfoot Trailers Jacksonville', city: 'Jacksonville', state: 'FL', isFactory: false },
  { code: 'ASHLAND', name: 'Bigfoot Trailers Ashland', city: 'Ashland', state: 'VA', isFactory: false },
  { code: 'ATLANTA', name: 'Bigfoot Trailers Atlanta', city: 'Atlanta', state: 'GA', isFactory: false },
];

// ── Trailer model seed data ─────────────────────────────────────────────────

const TRAILER_MODELS = [
  { code: 'XP_14ET', displayName: '14K ET XP', series: 'xp', weightRating: '14,000 lb' },
  { code: 'XP_175ET', displayName: '17.5K ET XP', series: 'xp', weightRating: '17,500 lb' },
  { code: 'YETI_15K', displayName: '15K Yeti', series: 'yeti', weightRating: '15,000 lb' },
  { code: 'YETI_18K', displayName: '18K Yeti', series: 'yeti', weightRating: '18,000 lb' },
  { code: 'YETI_21K', displayName: '21K Yeti', series: 'yeti', weightRating: '21,000 lb' },
  { code: 'DO_STANDARD', displayName: 'Deck Over', series: 'deck_over', weightRating: null },
  { code: 'GN_STANDARD', displayName: 'Gooseneck / Dump', series: 'gooseneck_dump', weightRating: null },
];

// ── Department seed data (20 departments) ───────────────────────────────────

const DEPARTMENTS: Array<{
  code: string;
  displayName: string;
  isQcStep: boolean;
  completionType: 'one_tap' | 'qc_checklist';
}> = [
  { code: 'XP_JIG', displayName: 'XP Jig Weld', isQcStep: false, completionType: 'one_tap' },
  { code: 'XP_FIN', displayName: 'XP Finish Weld', isQcStep: false, completionType: 'one_tap' },
  { code: 'YETI_JIG', displayName: 'Yeti Jig Weld', isQcStep: false, completionType: 'one_tap' },
  { code: 'YETI_FIN', displayName: 'Yeti Finish Weld', isQcStep: false, completionType: 'one_tap' },
  { code: 'DO_JIG', displayName: 'Deck Over Jig Weld', isQcStep: false, completionType: 'one_tap' },
  { code: 'DO_FIN', displayName: 'Deck Over Finish Weld', isQcStep: false, completionType: 'one_tap' },
  { code: 'GN_WELD', displayName: 'Gooseneck Jig Weld', isQcStep: false, completionType: 'one_tap' },
  { code: 'GN_FIN', displayName: 'Gooseneck Finish Weld', isQcStep: false, completionType: 'one_tap' },
  { code: 'PAINT_PREP', displayName: 'Paint Preparation', isQcStep: false, completionType: 'one_tap' },
  { code: 'PAINT_A', displayName: 'Paint Booth A', isQcStep: false, completionType: 'one_tap' },
  { code: 'PAINT_B', displayName: 'Paint Booth B', isQcStep: false, completionType: 'one_tap' },
  { code: 'HYDRAULICS', displayName: 'Hydraulics', isQcStep: false, completionType: 'one_tap' },
  { code: 'WIRE', displayName: 'Wire Department', isQcStep: false, completionType: 'one_tap' },
  { code: 'WOOD', displayName: 'Wood Department', isQcStep: false, completionType: 'one_tap' },
  { code: 'QC_1', displayName: 'Quality Control 1', isQcStep: true, completionType: 'qc_checklist' },
  { code: 'QC_2', displayName: 'Quality Control 2', isQcStep: true, completionType: 'qc_checklist' },
  { code: 'QC_3', displayName: 'Quality Control 3', isQcStep: true, completionType: 'qc_checklist' },
  { code: 'QC_4', displayName: 'Quality Control 4', isQcStep: true, completionType: 'qc_checklist' },
  { code: 'QC_5', displayName: 'Quality Control 5', isQcStep: true, completionType: 'qc_checklist' },
  { code: 'FINAL_QC', displayName: 'Final QC', isQcStep: true, completionType: 'qc_checklist' },
];

// ── Workflow template definitions (deptCode → stepOrder, per series) ────────

const WORKFLOW_STEPS: Record<string, Array<{ deptCode: string; stepOrder: number }>> = {
  xp: [
    { deptCode: 'XP_JIG', stepOrder: 1 }, { deptCode: 'QC_1', stepOrder: 2 },
    { deptCode: 'XP_FIN', stepOrder: 3 }, { deptCode: 'QC_2', stepOrder: 4 },
    { deptCode: 'PAINT_PREP', stepOrder: 5 }, { deptCode: 'QC_3', stepOrder: 6 },
    { deptCode: 'PAINT_A', stepOrder: 7 }, { deptCode: 'QC_4', stepOrder: 8 },
    { deptCode: 'WIRE', stepOrder: 9 }, { deptCode: 'QC_5', stepOrder: 10 },
    { deptCode: 'WOOD', stepOrder: 11 }, { deptCode: 'FINAL_QC', stepOrder: 12 },
  ],
  yeti: [
    { deptCode: 'YETI_JIG', stepOrder: 1 }, { deptCode: 'QC_1', stepOrder: 2 },
    { deptCode: 'YETI_FIN', stepOrder: 3 }, { deptCode: 'QC_2', stepOrder: 4 },
    { deptCode: 'PAINT_PREP', stepOrder: 5 }, { deptCode: 'QC_3', stepOrder: 6 },
    { deptCode: 'PAINT_A', stepOrder: 7 }, { deptCode: 'QC_4', stepOrder: 8 },
    { deptCode: 'WIRE', stepOrder: 9 }, { deptCode: 'QC_5', stepOrder: 10 },
    { deptCode: 'WOOD', stepOrder: 11 }, { deptCode: 'FINAL_QC', stepOrder: 12 },
  ],
  deck_over: [
    { deptCode: 'DO_JIG', stepOrder: 1 }, { deptCode: 'QC_1', stepOrder: 2 },
    { deptCode: 'DO_FIN', stepOrder: 3 }, { deptCode: 'QC_2', stepOrder: 4 },
    { deptCode: 'PAINT_PREP', stepOrder: 5 }, { deptCode: 'QC_3', stepOrder: 6 },
    { deptCode: 'PAINT_A', stepOrder: 7 }, { deptCode: 'QC_4', stepOrder: 8 },
    { deptCode: 'WIRE', stepOrder: 9 }, { deptCode: 'QC_5', stepOrder: 10 },
    { deptCode: 'WOOD', stepOrder: 11 }, { deptCode: 'FINAL_QC', stepOrder: 12 },
  ],
  gooseneck_dump: [
    { deptCode: 'GN_WELD', stepOrder: 1 }, { deptCode: 'QC_1', stepOrder: 2 },
    { deptCode: 'GN_FIN', stepOrder: 3 }, { deptCode: 'QC_2', stepOrder: 4 },
    { deptCode: 'PAINT_PREP', stepOrder: 5 }, { deptCode: 'QC_3', stepOrder: 6 },
    { deptCode: 'PAINT_B', stepOrder: 7 }, { deptCode: 'QC_4', stepOrder: 8 },
    { deptCode: 'HYDRAULICS', stepOrder: 9 }, { deptCode: 'QC_5', stepOrder: 10 },
    { deptCode: 'WOOD', stepOrder: 11 }, { deptCode: 'FINAL_QC', stepOrder: 12 },
  ],
};

// ── Stock customers seed data ───────────────────────────────────────────────

const STOCK_CUSTOMERS = [
  { name: 'Mulberry Stock', customerType: 'stock_location', smsOptOut: true },
  { name: 'Jacksonville Stock', customerType: 'stock_location', smsOptOut: true },
  { name: 'Ashland Stock', customerType: 'stock_location', smsOptOut: true },
  { name: 'Atlanta Stock', customerType: 'stock_location', smsOptOut: true },
];

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC API
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Idempotently seeds all reference data (locations, models, departments,
 * workflow_templates, stock customers). Safe to call multiple times.
 */
export async function seedReferenceData(prisma: PrismaService): Promise<void> {
  // 1. Locations
  await prisma.location.createMany({ data: LOCATIONS as any[], skipDuplicates: true });

  // 2. Trailer models
  await prisma.trailerModel.createMany({
    data: TRAILER_MODELS.map((m) => ({
      code: m.code,
      displayName: m.displayName,
      series: m.series as any,
      weightRating: m.weightRating,
    })),
    skipDuplicates: true,
  });

  // 3. Departments
  await prisma.department.createMany({
    data: DEPARTMENTS.map((d) => ({
      code: d.code,
      displayName: d.displayName,
      isQcStep: d.isQcStep,
      completionType: d.completionType as any,
    })),
    skipDuplicates: true,
  });

  // 4. Workflow templates — need department IDs resolved from codes
  const depts = await prisma.department.findMany({ select: { id: true, code: true } });
  const deptMap = new Map(depts.map((d) => [d.code, d.id]));

  for (const [series, steps] of Object.entries(WORKFLOW_STEPS)) {
    for (const step of steps) {
      const deptId = deptMap.get(step.deptCode);
      if (!deptId) continue;
      await prisma.workflowTemplate.upsert({
        where: { series_stepOrder: { series: series as any, stepOrder: step.stepOrder } },
        create: { series: series as any, departmentId: deptId, stepOrder: step.stepOrder },
        update: {},
      });
    }
  }

  // 5. Stock customers
  await prisma.customer.createMany({
    data: STOCK_CUSTOMERS.map((c) => ({
      name: c.name,
      customerType: c.customerType as any,
      smsOptOut: c.smsOptOut,
    })),
    skipDuplicates: true,
  });
}

/**
 * Creates one QC checklist item per QC department (appliesToSeries = 'all').
 * Returns a Map<departmentCode, checklistItemId> for use in QC inspections.
 */
export async function seedTestChecklistItems(
  prisma: PrismaService,
): Promise<Map<string, number>> {
  const qcDepts = await prisma.department.findMany({
    where: { isQcStep: true },
    select: { id: true, code: true },
  });

  const itemMap = new Map<string, number>();

  for (const dept of qcDepts) {
    const label = `E2E_QC_CHECK_${dept.code}`;

    const existing = await prisma.qcChecklistItem.findFirst({
      where: { itemLabel: label },
      select: { id: true },
    });

    if (existing) {
      itemMap.set(dept.code, existing.id);
    } else {
      const item = await prisma.qcChecklistItem.create({
        data: {
          departmentId: dept.id,
          appliesToSeries: 'all' as any,
          itemLabel: label,
          sortOrder: 0,
        },
        select: { id: true },
      });
      itemMap.set(dept.code, item.id);
    }
  }

  return itemMap;
}

/**
 * Deletes ALL transactional data from the test database.
 * Reference tables (locations, departments, trailer_models, workflow_templates,
 * customers) are preserved.
 *
 * ⚠ Only run against a dedicated test database!
 */
export async function cleanupTransactionalData(prisma: PrismaService): Promise<void> {
  // Delete in strict FK-dependency order (children first)
  await prisma.deliveryPhoto.deleteMany({});
  await prisma.locationReceipt.deleteMany({});
  await prisma.qcChecklistResult.deleteMany({});
  await prisma.qcPhoto.deleteMany({});
  await prisma.stepReversal.deleteMany({});
  await prisma.pushNotification.deleteMany({});
  await prisma.smsLog.deleteMany({});
  await prisma.workerMessage.deleteMany({});
  await prisma.payrollRecord.deleteMany({});
  await prisma.auditLog.deleteMany({});
  await prisma.qcInspection.deleteMany({});
  await prisma.delivery.deleteMany({});
  await prisma.deliveryBatch.deleteMany({});
  await prisma.pointValue.deleteMany({});
  await prisma.deptDollarRate.deleteMany({});
  await prisma.productionStep.deleteMany({});
  await prisma.trailerAddon.deleteMany({});
  await prisma.trailer.deleteMany({});
  await prisma.refreshToken.deleteMany({});
  await prisma.qcChecklistItem.deleteMany({});
  await prisma.user.deleteMany({});
}
