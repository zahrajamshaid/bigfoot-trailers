// =============================================================================
// BIGFOOT TRAILERS — Prisma Seed File
// Matches bigfoot_schema_final.sql INSERT statements exactly
// Seeds: 4 locations, 7 trailer models, 4 stock customers, 20 departments,
//        48 workflow templates (12 per series)
// =============================================================================

import 'dotenv/config';
import * as bcrypt from 'bcrypt';
import { PrismaClient, TrailerSeries, DeptCompletionType, CustomerType, UserRole, QcSeriesScope } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';

const connectionString = process.env['DATABASE_URL']!;
const adapter = new PrismaPg({ connectionString });
const prisma = new PrismaClient({ adapter });

async function main() {
  console.log('🌱 Seeding Bigfoot Trailers database...\n');

  // ─── LOCATIONS (5 rows) ────────────────────────────────────────────────────
  // shortLabel is the chip text shown in mobile pickers (Mul, Jax, VA, GA, TAL).
  const locations = await Promise.all([
    prisma.location.upsert({
      where: { code: 'MULBERRY' },
      update: { shortLabel: 'Mul' },
      create: {
        code: 'MULBERRY',
        name: 'Bigfoot Trailers Mulberry',
        city: 'Mulberry',
        state: 'FL',
        isFactory: true,
        shortLabel: 'Mul',
      },
    }),
    prisma.location.upsert({
      where: { code: 'JACKSONVILLE' },
      update: { shortLabel: 'Jax' },
      create: {
        code: 'JACKSONVILLE',
        name: 'Bigfoot Trailers Jacksonville',
        city: 'Jacksonville',
        state: 'FL',
        isFactory: false,
        shortLabel: 'Jax',
      },
    }),
    prisma.location.upsert({
      where: { code: 'TAPPAHANNOCK' },
      update: { shortLabel: 'VA' },
      create: {
        code: 'TAPPAHANNOCK',
        name: 'Bigfoot Trailers Tappahannock',
        city: 'Tappahannock',
        state: 'VA',
        isFactory: false,
        shortLabel: 'VA',
      },
    }),
    prisma.location.upsert({
      where: { code: 'ATLANTA' },
      update: { shortLabel: 'GA' },
      create: {
        code: 'ATLANTA',
        name: 'Bigfoot Trailers Atlanta',
        city: 'Atlanta',
        state: 'GA',
        isFactory: false,
        shortLabel: 'GA',
      },
    }),
    prisma.location.upsert({
      where: { code: 'TALLAHASSEE' },
      update: { shortLabel: 'TAL' },
      create: {
        code: 'TALLAHASSEE',
        name: 'Bigfoot Trailers Tallahassee',
        city: 'Tallahassee',
        state: 'FL',
        isFactory: false,
        shortLabel: 'TAL',
      },
    }),
  ]);
  console.log(`✅ Locations seeded: ${locations.length}`);

  // ─── TRAILER MODELS (7 rows) ──────────────────────────────────────────────
  const trailerModels = await Promise.all([
    prisma.trailerModel.upsert({
      where: { code: 'XP_14ET' },
      update: {},
      create: { code: 'XP_14ET', displayName: '14K ET XP', series: TrailerSeries.xp, weightRating: '14,000 lb' },
    }),
    prisma.trailerModel.upsert({
      where: { code: 'XP_175ET' },
      update: {},
      create: { code: 'XP_175ET', displayName: '17.5K ET XP', series: TrailerSeries.xp, weightRating: '17,500 lb' },
    }),
    prisma.trailerModel.upsert({
      where: { code: 'YETI_15K' },
      update: {},
      create: { code: 'YETI_15K', displayName: '15K Yeti', series: TrailerSeries.yeti, weightRating: '15,000 lb' },
    }),
    prisma.trailerModel.upsert({
      where: { code: 'YETI_18K' },
      update: {},
      create: { code: 'YETI_18K', displayName: '18K Yeti', series: TrailerSeries.yeti, weightRating: '18,000 lb' },
    }),
    prisma.trailerModel.upsert({
      where: { code: 'YETI_21K' },
      update: {},
      create: { code: 'YETI_21K', displayName: '21K Yeti', series: TrailerSeries.yeti, weightRating: '21,000 lb' },
    }),
    prisma.trailerModel.upsert({
      where: { code: 'DO_STANDARD' },
      update: {},
      create: { code: 'DO_STANDARD', displayName: 'Deck Over', series: TrailerSeries.deck_over, weightRating: null },
    }),
    prisma.trailerModel.upsert({
      where: { code: 'GN_STANDARD' },
      update: {},
      create: { code: 'GN_STANDARD', displayName: 'Gooseneck / Dump', series: TrailerSeries.gooseneck_dump, weightRating: null },
    }),
  ]);
  console.log(`✅ Trailer models seeded: ${trailerModels.length}`);

  // ─── CUSTOMERS — Stock locations (4 rows) ─────────────────────────────────
  // Customers have no natural unique key besides id.
  // Check by name+type to make seeding idempotent.
  const stockNames = [
    'Mulberry Stock',
    'Jacksonville Stock',
    'Tappahannock Stock',
    'Atlanta Stock',
    'Tallahassee Stock',
  ];
  for (const name of stockNames) {
    const existing = await prisma.customer.findFirst({
      where: { name, customerType: CustomerType.stock_location },
    });
    if (!existing) {
      await prisma.customer.create({
        data: { name, customerType: CustomerType.stock_location, smsOptOut: true },
      });
    }
  }
  console.log(`✅ Stock customers seeded: ${stockNames.length}`);

  // ─── DEPARTMENTS (20 rows) ────────────────────────────────────────────────
  // 14 production departments + 6 QC departments = 20 total
  const deptData: {
    code: string;
    displayName: string;
    isQcStep: boolean;
    completionType: DeptCompletionType;
  }[] = [
    { code: 'XP_JIG', displayName: 'XP Jig Weld', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'XP_FIN', displayName: 'XP Finish Weld', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'YETI_JIG', displayName: 'Yeti Jig Weld', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'YETI_FIN', displayName: 'Yeti Finish Weld', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'DO_JIG', displayName: 'Deck Over Jig Weld', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'DO_FIN', displayName: 'Deck Over Finish Weld', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'GN_WELD', displayName: 'Gooseneck Jig Weld', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'GN_FIN', displayName: 'Gooseneck Finish Weld', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'PAINT_PREP', displayName: 'Paint Preparation', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'PAINT_A', displayName: 'Paint Booth A', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'PAINT_B', displayName: 'Paint Booth B', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'HYDRAULICS', displayName: 'Hydraulics', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'WIRE', displayName: 'Wire Department', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'WOOD', displayName: 'Wood Department', isQcStep: false, completionType: DeptCompletionType.one_tap },
    { code: 'QC_1', displayName: 'Jig Weld QC', isQcStep: true, completionType: DeptCompletionType.qc_checklist },
    { code: 'QC_2', displayName: 'Finish Weld QC', isQcStep: true, completionType: DeptCompletionType.qc_checklist },
    { code: 'QC_3', displayName: 'Paint Prep QC', isQcStep: true, completionType: DeptCompletionType.qc_checklist },
    { code: 'QC_4', displayName: 'Paint QC', isQcStep: true, completionType: DeptCompletionType.qc_checklist },
    // QC_5 inspects WIRE for XP/Yeti/Deck Over and HYDRAULICS for Gooseneck —
    // hybrid label captures both contexts (the trailer's model on the queue
    // card tells the inspector which is being checked).
    { code: 'QC_5', displayName: 'Wire / Hydraulics QC', isQcStep: true, completionType: DeptCompletionType.qc_checklist },
    { code: 'FINAL_QC', displayName: 'Final QC', isQcStep: true, completionType: DeptCompletionType.qc_checklist },
  ];

  const departments: Record<string, { id: number }> = {};
  for (const dept of deptData) {
    const result = await prisma.department.upsert({
      where: { code: dept.code },
      update: {},
      create: dept,
    });
    departments[dept.code] = result;
  }
  console.log(`✅ Departments seeded: ${Object.keys(departments).length}`);

  // ─── WORKFLOW TEMPLATES (48 rows — 12 per series) ─────────────────────────
  // Each series has 6 production steps + 6 QC checkpoints = 12 total
  // On QC fail, inspector selects ANY department — routing is dynamic

  const workflowData: { series: TrailerSeries; deptCode: string; stepOrder: number }[] = [
    // XP Series: XP_JIG → QC_1 → XP_FIN → QC_2 → PAINT_PREP → QC_3 → PAINT_A → QC_4 → WIRE → QC_5 → WOOD → FINAL_QC
    { series: TrailerSeries.xp, deptCode: 'XP_JIG', stepOrder: 1 },
    { series: TrailerSeries.xp, deptCode: 'QC_1', stepOrder: 2 },
    { series: TrailerSeries.xp, deptCode: 'XP_FIN', stepOrder: 3 },
    { series: TrailerSeries.xp, deptCode: 'QC_2', stepOrder: 4 },
    { series: TrailerSeries.xp, deptCode: 'PAINT_PREP', stepOrder: 5 },
    { series: TrailerSeries.xp, deptCode: 'QC_3', stepOrder: 6 },
    { series: TrailerSeries.xp, deptCode: 'PAINT_A', stepOrder: 7 },
    { series: TrailerSeries.xp, deptCode: 'QC_4', stepOrder: 8 },
    { series: TrailerSeries.xp, deptCode: 'WIRE', stepOrder: 9 },
    { series: TrailerSeries.xp, deptCode: 'QC_5', stepOrder: 10 },
    { series: TrailerSeries.xp, deptCode: 'WOOD', stepOrder: 11 },
    { series: TrailerSeries.xp, deptCode: 'FINAL_QC', stepOrder: 12 },

    // Yeti Series: YETI_JIG → QC_1 → YETI_FIN → QC_2 → PAINT_PREP → QC_3 → PAINT_A → QC_4 → WIRE → QC_5 → WOOD → FINAL_QC
    { series: TrailerSeries.yeti, deptCode: 'YETI_JIG', stepOrder: 1 },
    { series: TrailerSeries.yeti, deptCode: 'QC_1', stepOrder: 2 },
    { series: TrailerSeries.yeti, deptCode: 'YETI_FIN', stepOrder: 3 },
    { series: TrailerSeries.yeti, deptCode: 'QC_2', stepOrder: 4 },
    { series: TrailerSeries.yeti, deptCode: 'PAINT_PREP', stepOrder: 5 },
    { series: TrailerSeries.yeti, deptCode: 'QC_3', stepOrder: 6 },
    { series: TrailerSeries.yeti, deptCode: 'PAINT_A', stepOrder: 7 },
    { series: TrailerSeries.yeti, deptCode: 'QC_4', stepOrder: 8 },
    { series: TrailerSeries.yeti, deptCode: 'WIRE', stepOrder: 9 },
    { series: TrailerSeries.yeti, deptCode: 'QC_5', stepOrder: 10 },
    { series: TrailerSeries.yeti, deptCode: 'WOOD', stepOrder: 11 },
    { series: TrailerSeries.yeti, deptCode: 'FINAL_QC', stepOrder: 12 },

    // Deck Over: DO_JIG → QC_1 → DO_FIN → QC_2 → PAINT_PREP → QC_3 → PAINT_A → QC_4 → WIRE → QC_5 → WOOD → FINAL_QC
    { series: TrailerSeries.deck_over, deptCode: 'DO_JIG', stepOrder: 1 },
    { series: TrailerSeries.deck_over, deptCode: 'QC_1', stepOrder: 2 },
    { series: TrailerSeries.deck_over, deptCode: 'DO_FIN', stepOrder: 3 },
    { series: TrailerSeries.deck_over, deptCode: 'QC_2', stepOrder: 4 },
    { series: TrailerSeries.deck_over, deptCode: 'PAINT_PREP', stepOrder: 5 },
    { series: TrailerSeries.deck_over, deptCode: 'QC_3', stepOrder: 6 },
    { series: TrailerSeries.deck_over, deptCode: 'PAINT_A', stepOrder: 7 },
    { series: TrailerSeries.deck_over, deptCode: 'QC_4', stepOrder: 8 },
    { series: TrailerSeries.deck_over, deptCode: 'WIRE', stepOrder: 9 },
    { series: TrailerSeries.deck_over, deptCode: 'QC_5', stepOrder: 10 },
    { series: TrailerSeries.deck_over, deptCode: 'WOOD', stepOrder: 11 },
    { series: TrailerSeries.deck_over, deptCode: 'FINAL_QC', stepOrder: 12 },

    // Gooseneck/Dump: GN_WELD → QC_1 → GN_FIN → QC_2 → PAINT_PREP → QC_3 → PAINT_B → QC_4 → HYDRAULICS → QC_5 → WOOD → FINAL_QC
    { series: TrailerSeries.gooseneck_dump, deptCode: 'GN_WELD', stepOrder: 1 },
    { series: TrailerSeries.gooseneck_dump, deptCode: 'QC_1', stepOrder: 2 },
    { series: TrailerSeries.gooseneck_dump, deptCode: 'GN_FIN', stepOrder: 3 },
    { series: TrailerSeries.gooseneck_dump, deptCode: 'QC_2', stepOrder: 4 },
    { series: TrailerSeries.gooseneck_dump, deptCode: 'PAINT_PREP', stepOrder: 5 },
    { series: TrailerSeries.gooseneck_dump, deptCode: 'QC_3', stepOrder: 6 },
    { series: TrailerSeries.gooseneck_dump, deptCode: 'PAINT_B', stepOrder: 7 },
    { series: TrailerSeries.gooseneck_dump, deptCode: 'QC_4', stepOrder: 8 },
    { series: TrailerSeries.gooseneck_dump, deptCode: 'HYDRAULICS', stepOrder: 9 },
    { series: TrailerSeries.gooseneck_dump, deptCode: 'QC_5', stepOrder: 10 },
    { series: TrailerSeries.gooseneck_dump, deptCode: 'WOOD', stepOrder: 11 },
    { series: TrailerSeries.gooseneck_dump, deptCode: 'FINAL_QC', stepOrder: 12 },
  ];

  let workflowCount = 0;
  for (const wf of workflowData) {
    const dept = departments[wf.deptCode];
    if (!dept) {
      throw new Error(`Department not found for code: ${wf.deptCode}`);
    }
    await prisma.workflowTemplate.upsert({
      where: {
        series_stepOrder: {
          series: wf.series,
          stepOrder: wf.stepOrder,
        },
      },
      update: {},
      create: {
        series: wf.series,
        departmentId: dept.id,
        stepOrder: wf.stepOrder,
      },
    });
    workflowCount++;
  }
  console.log(`✅ Workflow templates seeded: ${workflowCount}`);

  // ─── QC CHECKLIST ITEMS ───────────────────────────────────────────────────
  // Authoritative Bigfoot QC forms — two variants:
  //   • XP / Yeti ET  → scope: xp + yeti
  //   • Deckover      → scope: deck_over
  // Six QC departments cover every series: QC_1 (Main Jig) → QC_2 (Finish
  // Weld) → QC_3 (Paint Prep) → QC_4 (Paint) → QC_5 (Wiring) → FINAL_QC
  // (Wood + Critical Fail).
  // Idempotent: re-running the seed updates sort_order / re-activates
  // without duplicating, and leaves inspection history intact.

  type ChecklistItem = { label: string; requiresAddonKey?: string | null };
  type ChecklistSection = { deptCode: string; items: (string | ChecklistItem)[] };

  async function seedChecklist(
    sections: ChecklistSection[],
    scopes: QcSeriesScope[],
    startSortOrder = 1,
  ): Promise<number> {
    let n = 0;
    for (const section of sections) {
      const dept = departments[section.deptCode];
      if (!dept) {
        throw new Error(`Department not found for checklist: ${section.deptCode}`);
      }
      for (let i = 0; i < section.items.length; i++) {
        const raw = section.items[i];
        const label = typeof raw === 'string' ? raw : raw.label;
        const requiresAddonKey =
          typeof raw === 'string' ? null : (raw.requiresAddonKey ?? null);
        const sortOrder = startSortOrder + i;
        for (const scope of scopes) {
          const existing = await prisma.qcChecklistItem.findFirst({
            where: {
              departmentId: dept.id,
              itemLabel: label,
              appliesToSeries: scope,
              // Match on requires_addon_key so the same label can exist both as
              // a base item and an option-gated one without collision.
              requiresAddonKey,
            },
            select: { id: true },
          });
          if (existing) {
            await prisma.qcChecklistItem.update({
              where: { id: existing.id },
              data: { sortOrder, isActive: true, requiresAddonKey },
            });
          } else {
            await prisma.qcChecklistItem.create({
              data: {
                departmentId: dept.id,
                itemLabel: label,
                sortOrder,
                appliesToSeries: scope,
                isActive: true,
                requiresAddonKey,
              },
            });
          }
          n++;
        }
      }
    }
    return n;
  }

  // ── XP / Yeti ET Checklist ──────────────────────────────────────────────
  const xpYetiSections: ChecklistSection[] = [
    {
      deptCode: 'QC_1', // MAIN JIG QC
      items: [
        'Sales order attached',
        'Model, length, GVWR match order',
        'Frame square (corner-to-corner)',
        'Axle centerline square to frame',
        'Axle spacing correct',
        'Dovetail level (if equipped)',
        'Tongue centered',
        'All crossmembers installed',
        'Wood crossmembers installed correctly',
        'Extra crossmembers added if required (>22 ft)',
        'Correct axles installed',
        'Axles facing correct direction (brakes rear)',
        'Hangers welded correctly',
        'Equalizers installed correctly',
        'Hanger bolts tight',
        'Coupler plate square and welded',
        'Safety chain mounts welded',
        'Chain stays welded',
        'Chain holders welded',
        'All plasma slag removed',
        'No defects left unrepaired',
        'Weld number present and legible',
      ],
    },
    {
      deptCode: 'QC_2', // FINISH WELD QC
      items: [
        'All weld seams complete (no gaps)',
        'Welds clean (no slag or splatter)',
        'Weld penetration acceptable',
        'Ramps straight',
        'Hinges welded inside & outside',
        'Ramp rings welded top & bottom',
        'Correct springs installed',
        'Handles installed',
        'Grease zerks installed',
        'Ramp length correct',
        'Ramp leg length correct',
        'Fenders level and straight',
        'Fender supports welded (inside & out)',
        'Gussets installed where required',
        'Steps welded',
        'Tag holder installed',
        'Wire holders welded',
        'Stake pockets correct quantity & placement',
        'Spare tire mount correct location',
        'Toolbox pan welded (if equipped)',
        'Correct jack installed',
        'Jack handle tight',
        'Hole cut for wiring',
        'Correct seams on trailer',
        'Correct number of seams',
      ],
    },
    {
      deptCode: 'QC_3', // PAINT PREP QC
      items: [
        'Work order attached (required)',
        'All weld spatter removed',
        'Mill scale removed (needle scaler if needed)',
        'Rough welds smoothed',
        'Sharp edges rounded',
        'Rust removed',
        'Oil and grease removed',
        'Welding wire removed',
        'Flat surfaces cleaned with flap disc',
        'High-visibility areas smoothed',
        'Clean & Etch applied correctly',
        '3-5 minute dwell time',
        'Did not dry',
        'Pressure washed completely',
        'Rewashed if needed',
        'No dirt, oil, shavings, rust, or splatter',
        'Toolbox interior cleaned (if equipped)',
        'Toolbox lid edges smooth (if equipped)',
      ],
    },
    {
      deptCode: 'QC_4', // PAINT QC
      items: [
        'Full frame coverage',
        'Underside coated',
        'Inside stake pockets coated',
        'No runs',
        'No dry spray',
        'No thin spots',
        'Tongue finish clean',
        'Toolbox finish clean (if equipped)',
        'Fender finish clean',
        'Paint thickness checked',
      ],
    },
    {
      deptCode: 'QC_5', // WIRING QC
      items: [
        'Work order verified',
        'Wiring secured with zip ties',
        'Wires in protective loom',
        'Rubber grommets installed',
        'Gold pins installed correctly',
        'Brake box installed',
        'Breakaway cable installed',
        'Charging wire to battery installed',
        'Battery charger connected',
        'All lights working',
        'Brake output ~3 amps',
        'Turn and marker lights working',
        'Safety chains installed',
        'All decals / stickers applied',
      ],
    },
    {
      deptCode: 'FINAL_QC', // WOOD / FINAL QC + CRITICAL FAIL CONDITIONS
      items: [
        'Boards crown up',
        'Boards oriented consistently',
        'Even spacing between boards',
        'Three rows of screws per board',
        'Screws tight',
        'Seams over crossmembers',
        'Seams bolted',
        'Correct tires installed',
        'Lug nuts torqued',
        'Torque paint applied',
        'Spare tire installed (per order)',
        'Axle caps installed and undamaged',
        'Coupler bolts tight',
        'Touch-up paint applied underneath',
        'Jack handle end painted',
        'CRITICAL FAIL: Frame not square',
        'CRITICAL FAIL: Axles not aligned',
        'CRITICAL FAIL: Missing welds',
        'CRITICAL FAIL: Brakes not working',
        'CRITICAL FAIL: Lights not working',
        'CRITICAL FAIL: Breakaway not working',
        'CRITICAL FAIL: Wrong components installed',
        'CRITICAL FAIL: Missing required parts',
      ],
    },
  ];

  // ── Deckover Checklist ──────────────────────────────────────────────────
  const deckoverSections: ChecklistSection[] = [
    {
      deptCode: 'QC_1', // MAIN JIG QC
      items: [
        'Sales order attached',
        'Model, length, GVWR match order',
        'Frame square (corner-to-corner)',
        'Axle centerline square to frame',
        'Axle spacing correct',
        'Tongue centered',
        'All crossmembers installed',
        'Wood crossmembers installed correctly',
        'Correct axles installed',
        'Axles facing correct direction (brakes rear)',
        'Hangers welded correctly',
        'Equalizers installed correctly',
        'Hanger bolts tight',
        'Main frame correct (I-beam/channel per spec)',
        'Frame straight (no twist or bow)',
        'Coupler plate square and welded',
        'Safety chain mounts welded',
        'Chain stays welded',
        'Chain holders welded',
        'All plasma slag removed',
        'No defects left unrepaired',
        'Weld number present and legible',
      ],
    },
    {
      deptCode: 'QC_2', // FINISH WELD QC
      items: [
        'All weld seams complete (no gaps)',
        'Welds clean (no slag or splatter)',
        'Weld penetration acceptable',
        'Deck frame fully welded',
        'Deck frame square to main frame',
        'Deck frame sits flat (no twist or rocking)',
        'Ramp system matches sales order',
        'Ramps straight (if equipped)',
        'Ramp hinges welded inside & outside (flip-up / beast)',
        'Ramp pivot points aligned (flip-up / beast)',
        'Ramp rings welded top & bottom (if equipped)',
        'Correct springs installed (flip-up / beast)',
        'Handles installed (if equipped)',
        'Grease zerks installed (if equipped)',
        'Ramp length correct',
        'Ramp leg length correct (if applicable)',
        'Slide-in ramp channels installed and aligned (slide-in)',
        'Slide-in ramps fit properly and secure (slide-in)',
        'Rub rail installed straight and fully welded',
        'Stake pockets correct quantity & placement',
        'D-rings installed and welded properly (if equipped)',
        'Steps welded',
        'Tag holder installed',
        'Wire holders welded',
        'Spare tire mount correct location',
        'Toolbox mounted and welded (if equipped)',
        'Correct jack installed',
        'Jack handle tight',
        'Hole cut for wiring',
        'Correct seams on trailer',
        'Correct number of seams',
      ],
    },
    {
      deptCode: 'QC_3', // PAINT PREP QC
      items: [
        'Work order attached (required)',
        'All weld spatter removed',
        'Mill scale removed (needle scaler if needed)',
        'Rough welds smoothed',
        'Sharp edges rounded',
        'Rust removed',
        'Oil and grease removed',
        'Welding wire removed',
        'Flat surfaces cleaned with flap disc',
        'High-visibility areas smoothed',
        'Clean & Etch applied correctly',
        '3-5 minute dwell time',
        'Did not dry',
        'Pressure washed completely',
        'Rewashed if needed',
        'No dirt, oil, shavings, rust, or splatter',
        'Toolbox interior cleaned (if equipped)',
        'Toolbox lid edges smooth (if equipped)',
      ],
    },
    {
      deptCode: 'QC_4', // PAINT QC
      items: [
        'Full frame coverage',
        'Underside coated',
        'Inside stake pockets coated',
        'No runs',
        'No dry spray',
        'No thin spots',
        'Deck surface finish clean',
        'Rub rail finish clean',
        'Fender/axle area finish clean',
        'Paint thickness checked',
      ],
    },
    {
      deptCode: 'QC_5', // WIRING QC
      items: [
        'Work order verified',
        'Wiring secured with zip ties',
        'Wires in protective loom',
        'Rubber grommets installed',
        'Gold pins installed correctly',
        'Brake box installed',
        'Breakaway cable installed',
        'Charging wire to battery installed',
        'Battery charger connected',
        'All lights working',
        'Brake output ~3 amps',
        'Turn and marker lights working',
        'Safety chains installed',
        'All decals / stickers applied',
      ],
    },
    {
      deptCode: 'FINAL_QC', // WOOD / FINAL QC + CRITICAL FAIL CONDITIONS
      items: [
        'Boards crown up',
        'Boards oriented consistently',
        'Even spacing between boards',
        'Three rows of screws per board',
        'Screws tight',
        'Seams over crossmembers',
        'Seams bolted',
        'Deck surface level across full width',
        'No board movement or flex',
        'Ramps deploy and store properly',
        'Ramps secure properly in transport position',
        'Slide-in ramps insert/remove smoothly (if equipped)',
        'No excessive movement in ramps',
        'Correct tires installed',
        'Lug nuts torqued',
        'Torque paint applied',
        'Spare tire installed (per order)',
        'Axle caps installed and undamaged',
        'Coupler bolts tight',
        'Touch-up paint applied underneath',
        'Jack handle end painted',
        'CRITICAL FAIL: Frame not square',
        'CRITICAL FAIL: Axles not aligned',
        'CRITICAL FAIL: Missing welds',
        'CRITICAL FAIL: Brakes not working',
        'CRITICAL FAIL: Lights not working',
        'CRITICAL FAIL: Breakaway not working',
        'CRITICAL FAIL: Ramps do not function properly',
        'CRITICAL FAIL: Deck not level or secure',
        'CRITICAL FAIL: Wrong components installed',
        'CRITICAL FAIL: Missing required parts',
      ],
    },
  ];

  // ── Dump Checklist (gooseneck_dump series) ──────────────────────────────
  const dumpSections: ChecklistSection[] = [
    {
      deptCode: 'QC_1', // MAIN JIG QC
      items: [
        'Sales order attached',
        'Model, length, GVWR match order',
        'Frame square (corner-to-corner)',
        'Axle centerline square to frame',
        'Axle spacing correct',
        'Tongue centered',
        'All crossmembers installed',
        'Floor supports installed correctly',
        'Correct axles installed',
        'Axles facing correct direction (brakes rear)',
        'Hangers welded correctly',
        'Equalizers installed correctly',
        'Hanger bolts tight',
        'Main frame correct (channel/I-beam per spec)',
        'Frame straight (no twist or bow)',
        'Coupler plate square and welded',
        'Safety chain mounts welded',
        'Chain stays welded',
        'Chain holders welded',
        'All plasma slag removed',
        'No defects left unrepaired',
        'Weld number present and legible',
      ],
    },
    {
      deptCode: 'QC_2', // FINISH WELD QC
      items: [
        'All weld seams complete (no gaps)',
        'Welds clean (no slag or splatter)',
        'Weld penetration acceptable',
        'Dump bed frame fully welded',
        'Dump bed square to main frame',
        'Bed sits flat on frame (no rocking)',
        'Hinge tube aligned straight across frame',
        'Hinge tube fully welded and clean',
        'Hinge brackets aligned and welded correctly',
        'Bed side walls welded straight',
        'Front wall square and welded',
        'Tailgate hinges aligned and welded',
        'Tailgate opens and closes properly',
        'Tailgate latches function correctly',
        'Fenders level and straight',
        'Fender supports welded (inside & out)',
        'Gussets installed where required',
        'Steps welded',
        'Tag holder installed',
        'Wire holders welded',
        'Hydraulic hose holders welded',
        'Stake pockets correct quantity & placement (if equipped)',
        'Spare tire mount correct location',
        'Toolbox mounted and welded (if equipped)',
        'Correct jack installed',
        'Jack handle tight',
        'Hole cut for wiring',
        'Correct seams on trailer',
        'Correct number of seams',
      ],
    },
    {
      deptCode: 'QC_3', // PAINT PREP QC
      items: [
        'Work order attached (required)',
        'All weld spatter removed',
        'Mill scale removed (needle scaler if needed)',
        'Rough welds smoothed',
        'Sharp edges rounded',
        'Rust removed',
        'Oil and grease removed',
        'Welding wire removed',
        'Flat surfaces cleaned with flap disc',
        'High-visibility areas smoothed (bed sides, toolbox)',
        'Clean & Etch applied correctly',
        '3-5 minute dwell time',
        'Did not dry',
        'Pressure washed completely',
        'Rewashed if needed',
        'No dirt, oil, shavings, rust, or splatter',
        'Toolbox interior cleaned (if equipped)',
        'Toolbox lid edges smooth (if equipped)',
      ],
    },
    {
      deptCode: 'QC_4', // PAINT QC
      items: [
        'Full frame coverage',
        'Underside coated',
        'Inside bed coated',
        'No runs',
        'No dry spray',
        'No thin spots',
        'Bed interior finish acceptable',
        'Bed sides finish clean',
        'Fender finish clean',
        'Paint thickness checked',
      ],
    },
    {
      deptCode: 'QC_5', // WIRING & HYDRAULICS QC
      items: [
        'Work order verified',
        'Wiring secured with zip ties',
        'Wires in protective loom',
        'Rubber grommets installed',
        'Gold pins installed correctly',
        'Brake box installed',
        'Breakaway cable installed',
        'Charging wire to battery installed',
        'Battery charger connected',
        'All lights working',
        'Brake output ~3 amps',
        'Turn and marker lights working',
        'Safety chains installed',
        'All decals / stickers applied',
        'Pump secured',
        'Battery secured',
        'Battery charged',
        'All electrical connections tight',
        'All hydraulic fittings tight',
        'No hydraulic leaks',
        'Hoses routed clean (no pinch points)',
        'Hoses secured and protected',
        'Cylinder mounted secure',
        'Cylinder pins secured with clips',
        'Pump operates properly',
        'Bed raises smoothly',
        'Bed lowers smoothly',
        'Bed raises to full height',
        'Bed holds position (no drop)',
        'Bed returns fully to frame',
        'Safety prop / support installed and functional',
        'Tarp system installed and operates properly (if equipped)',
      ],
    },
    {
      deptCode: 'FINAL_QC', // FINAL QC + CRITICAL FAIL CONDITIONS
      items: [
        'Bed cycles multiple times without issue',
        'No interference during lift or lower',
        'Tailgate opens and closes properly',
        'Tailgate latches secure properly',
        'Trailer sits level',
        'No abnormal noises during operation',
        'All components installed per order',
        'Trailer clean and ready for delivery',
        'CRITICAL FAIL: Frame not square',
        'CRITICAL FAIL: Axles not aligned',
        'CRITICAL FAIL: Missing welds',
        'CRITICAL FAIL: Brakes not working',
        'CRITICAL FAIL: Lights not working',
        'CRITICAL FAIL: Breakaway not working',
        'CRITICAL FAIL: ANY hydraulic leak',
        'CRITICAL FAIL: Bed does not raise or lower correctly',
        'CRITICAL FAIL: Bed does not hold position',
        'CRITICAL FAIL: Tailgate does not latch',
        'CRITICAL FAIL: Wrong components installed',
        'CRITICAL FAIL: Missing required parts',
      ],
    },
  ];

  // ── Options Checklist (appended to FINAL_QC, gated by trailer addons) ───
  // Canonical addon keys — trailer_addons.addon_name must match for the item
  // to appear on the inspection form. '*' = appears whenever any addon is
  // present (e.g. the "options match sales order" check). Scope = all so
  // these are evaluated for every trailer series.
  //
  // Sort order starts at 1000 so these always render below the base
  // FINAL_QC items regardless of series-specific length.
  const optionsSections: ChecklistSection[] = [
    {
      deptCode: 'FINAL_QC',
      items: [
        // OPTIONS QC — wildcard (any addon present)
        { label: 'All installed options match sales order', requiresAddonKey: '*' },

        // FORK POCKETS
        { label: 'Fork pockets installed in correct location', requiresAddonKey: 'fork_pockets' },
        { label: 'Fork pockets square and aligned', requiresAddonKey: 'fork_pockets' },
        { label: 'Fork pockets fully welded and secure', requiresAddonKey: 'fork_pockets' },
        { label: 'Fork pockets — no weld defects or sharp edges', requiresAddonKey: 'fork_pockets' },

        // HYDRAULIC JACK
        { label: 'Hydraulic jack mounted square and secure', requiresAddonKey: 'hydraulic_jack' },
        { label: 'Hydraulic jack cylinder pins secured with clips', requiresAddonKey: 'hydraulic_jack' },
        { label: 'Hydraulic jack raises and lowers properly', requiresAddonKey: 'hydraulic_jack' },
        { label: 'Hydraulic jack — no hydraulic leaks', requiresAddonKey: 'hydraulic_jack' },
        { label: 'Hydraulic jack hoses routed clean (no pinch points)', requiresAddonKey: 'hydraulic_jack' },
        { label: 'Hydraulic jack hoses secured and protected', requiresAddonKey: 'hydraulic_jack' },
        { label: 'Hydraulic jack controls operate correctly', requiresAddonKey: 'hydraulic_jack' },

        // HYDRAULIC RAMPS
        { label: 'Ramp cylinders mounted secure', requiresAddonKey: 'hydraulic_ramps' },
        { label: 'Ramp cylinder pins secured with clips', requiresAddonKey: 'hydraulic_ramps' },
        { label: 'Ramps raise and lower smoothly', requiresAddonKey: 'hydraulic_ramps' },
        { label: 'Ramps fully open and close', requiresAddonKey: 'hydraulic_ramps' },
        { label: 'Hydraulic ramps — no hydraulic leaks', requiresAddonKey: 'hydraulic_ramps' },
        { label: 'Hydraulic ramp hoses routed clean (no pinch points)', requiresAddonKey: 'hydraulic_ramps' },
        { label: 'Hydraulic ramp hoses secured and protected', requiresAddonKey: 'hydraulic_ramps' },
        { label: 'Hydraulic ramps lock/secure properly in transport position', requiresAddonKey: 'hydraulic_ramps' },

        // DROP-IN TOOLBOX
        { label: 'Drop-in toolbox installed square and secure', requiresAddonKey: 'drop_in_toolbox' },
        { label: 'Drop-in toolbox mounting points secure', requiresAddonKey: 'drop_in_toolbox' },
        { label: 'Drop-in toolbox lid opens and closes smoothly', requiresAddonKey: 'drop_in_toolbox' },
        { label: 'Drop-in toolbox latches function properly', requiresAddonKey: 'drop_in_toolbox' },
        { label: 'Drop-in toolbox weather seal installed correctly', requiresAddonKey: 'drop_in_toolbox' },
        { label: 'Drop-in toolbox — no sharp edges inside', requiresAddonKey: 'drop_in_toolbox' },

        // ELECTRIC TARP
        { label: 'Electric tarp system mounted secure', requiresAddonKey: 'electric_tarp' },
        { label: 'Electric tarp motor operates properly', requiresAddonKey: 'electric_tarp' },
        { label: 'Electric tarp rolls out and retracts smoothly', requiresAddonKey: 'electric_tarp' },
        { label: 'Electric tarp fully covers bed', requiresAddonKey: 'electric_tarp' },
        { label: 'Electric tarp wiring secured and protected', requiresAddonKey: 'electric_tarp' },
        { label: 'Electric tarp switch/control operates properly', requiresAddonKey: 'electric_tarp' },

        // WINCH MOUNT
        { label: 'Winch mount installed in correct location', requiresAddonKey: 'winch_mount' },
        { label: 'Winch mount fully welded or bolted secure', requiresAddonKey: 'winch_mount' },
        { label: 'Winch mount plate flat and aligned', requiresAddonKey: 'winch_mount' },
        { label: 'Winch mount — no weld defects or flex', requiresAddonKey: 'winch_mount' },

        // CRITICAL FAIL CONDITIONS — apply whenever any option is present
        { label: 'CRITICAL FAIL (OPTIONS): Any option missing from order', requiresAddonKey: '*' },
        { label: 'CRITICAL FAIL (OPTIONS): Any loose or unsecured component', requiresAddonKey: '*' },
        { label: 'CRITICAL FAIL (OPTIONS): Any hydraulic leak', requiresAddonKey: '*' },
        { label: 'CRITICAL FAIL (OPTIONS): Any option not functioning properly', requiresAddonKey: '*' },
        { label: 'CRITICAL FAIL (OPTIONS): Wiring exposed or unsecured', requiresAddonKey: '*' },
      ],
    },
  ];

  const xpYetiCount = await seedChecklist(xpYetiSections, [
    QcSeriesScope.xp,
    QcSeriesScope.yeti,
  ]);
  const deckoverCount = await seedChecklist(deckoverSections, [
    QcSeriesScope.deck_over,
  ]);
  const dumpCount = await seedChecklist(dumpSections, [
    QcSeriesScope.gooseneck_dump,
  ]);
  const optionsCount = await seedChecklist(
    optionsSections,
    [QcSeriesScope.all],
    1000,
  );
  console.log(
    `✅ QC checklist items seeded: ${xpYetiCount} (xp+yeti), ${deckoverCount} (deck_over), ${dumpCount} (gooseneck_dump), ${optionsCount} (options — FINAL_QC)`,
  );

  // ── Self-check items for upstream (non-QC) departments ─────────────────
  // Each production department completes the same checklist items that its
  // downstream QC stage will verify. The worker self-confirms each item at
  // step completion; the QC manager reviews & makes the pass/fail call.
  const UPSTREAM_MAP: Partial<Record<QcSeriesScope, Record<string, string>>> = {
    [QcSeriesScope.xp]: {
      QC_1: 'XP_JIG',
      QC_2: 'XP_FIN',
      QC_3: 'PAINT_PREP',
      QC_4: 'PAINT_A',
      QC_5: 'WIRE',
      FINAL_QC: 'WOOD',
    },
    [QcSeriesScope.yeti]: {
      QC_1: 'YETI_JIG',
      QC_2: 'YETI_FIN',
      QC_3: 'PAINT_PREP',
      QC_4: 'PAINT_A',
      QC_5: 'WIRE',
      FINAL_QC: 'WOOD',
    },
    [QcSeriesScope.deck_over]: {
      QC_1: 'DO_JIG',
      QC_2: 'DO_FIN',
      QC_3: 'PAINT_PREP',
      QC_4: 'PAINT_A',
      QC_5: 'WIRE',
      FINAL_QC: 'WOOD',
    },
    [QcSeriesScope.gooseneck_dump]: {
      QC_1: 'GN_WELD',
      QC_2: 'GN_FIN',
      QC_3: 'PAINT_PREP',
      QC_4: 'PAINT_B',
      QC_5: 'HYDRAULICS',
      FINAL_QC: 'WOOD',
    },
  };

  async function seedUpstreamChecklist(
    sections: ChecklistSection[],
    scopes: QcSeriesScope[],
    startSortOrder = 1,
  ): Promise<number> {
    let n = 0;
    for (const section of sections) {
      for (let i = 0; i < section.items.length; i++) {
        const raw = section.items[i];
        const label = typeof raw === 'string' ? raw : raw.label;
        const requiresAddonKey =
          typeof raw === 'string' ? null : (raw.requiresAddonKey ?? null);
        const sortOrder = startSortOrder + i;
        for (const scope of scopes) {
          const upstreamCode = UPSTREAM_MAP[scope]?.[section.deptCode];
          if (!upstreamCode) continue;
          const upstreamDept = departments[upstreamCode];
          if (!upstreamDept) {
            throw new Error(`Upstream dept not found: ${upstreamCode}`);
          }
          const existing = await prisma.qcChecklistItem.findFirst({
            where: {
              departmentId: upstreamDept.id,
              itemLabel: label,
              appliesToSeries: scope,
              requiresAddonKey,
            },
            select: { id: true },
          });
          if (existing) {
            await prisma.qcChecklistItem.update({
              where: { id: existing.id },
              data: { sortOrder, isActive: true, requiresAddonKey },
            });
          } else {
            await prisma.qcChecklistItem.create({
              data: {
                departmentId: upstreamDept.id,
                itemLabel: label,
                sortOrder,
                appliesToSeries: scope,
                isActive: true,
                requiresAddonKey,
              },
            });
          }
          n++;
        }
      }
    }
    return n;
  }

  const xpYetiUpstreamCount = await seedUpstreamChecklist(xpYetiSections, [
    QcSeriesScope.xp,
    QcSeriesScope.yeti,
  ]);
  const deckoverUpstreamCount = await seedUpstreamChecklist(
    deckoverSections,
    [QcSeriesScope.deck_over],
  );
  const dumpUpstreamCount = await seedUpstreamChecklist(dumpSections, [
    QcSeriesScope.gooseneck_dump,
  ]);
  console.log(
    `✅ Upstream self-check items seeded: ${xpYetiUpstreamCount} (xp+yeti), ${deckoverUpstreamCount} (deck_over), ${dumpUpstreamCount} (gooseneck_dump)`,
  );

  // ─── DEV USERS (one per role) ─────────────────────────────────────────────
  // Password for ALL dev accounts: Dev1234!
  const DEV_PASSWORD = 'Dev1234!';
  const passwordHash = await bcrypt.hash(DEV_PASSWORD, 12);
  const ADMIN_PASSWORD = 'Admin123!';
  const adminPasswordHash = await bcrypt.hash(ADMIN_PASSWORD, 12);

  const factory = locations.find((l) => l.code === 'MULBERRY')!;

  const devUserData: {
    email: string;
    fullName: string;
    role: UserRole;
    primaryDepartmentId: number | null;
    passwordHash?: string;
  }[] = [
    {
      email: 'admin@bigfoottrailers.com',
      fullName: 'Admin Owner',
      role: UserRole.owner,
      primaryDepartmentId: null,
      passwordHash: adminPasswordHash,
    },
    {
      email: 'owner@bigfoot.dev',
      fullName: 'Dev Owner',
      role: UserRole.owner,
      primaryDepartmentId: null,
    },
    {
      email: 'manager@bigfoot.dev',
      fullName: 'Dev Production Manager',
      role: UserRole.production_manager,
      primaryDepartmentId: null,
    },
    {
      email: 'transport@bigfoot.dev',
      fullName: 'Dev Transport Manager',
      role: UserRole.transport_manager,
      primaryDepartmentId: null,
    },
    {
      email: 'qc@bigfoot.dev',
      fullName: 'Dev QC Inspector',
      role: UserRole.qc_inspector,
      primaryDepartmentId: departments['QC_1'].id,
    },
    {
      email: 'worker@bigfoot.dev',
      fullName: 'Dev Worker',
      role: UserRole.worker,
      primaryDepartmentId: departments['XP_JIG'].id,
    },
    {
      email: 'driver@bigfoot.dev',
      fullName: 'Dev Driver',
      role: UserRole.driver,
      primaryDepartmentId: null,
    },
    {
      email: 'sales@bigfoot.dev',
      fullName: 'Dev Sales',
      role: UserRole.sales,
      primaryDepartmentId: null,
    },
    {
      email: 'office@bigfoot.dev',
      fullName: 'Dev Office',
      role: UserRole.office,
      primaryDepartmentId: null,
    },
  ];

  for (const u of devUserData) {
    await prisma.user.upsert({
      where: { email: u.email },
      update: { passwordHash: u.passwordHash ?? passwordHash, fullName: u.fullName, role: u.role, primaryLocationId: factory.id, primaryDepartmentId: u.primaryDepartmentId, isActive: true },
      create: {
        email: u.email,
        fullName: u.fullName,
        passwordHash: u.passwordHash ?? passwordHash,
        role: u.role,
        primaryLocationId: factory.id,
        primaryDepartmentId: u.primaryDepartmentId,
        isActive: true,
      },
    });
  }
  console.log(`✅ Dev users seeded: ${devUserData.length} (password: ${DEV_PASSWORD})`);

  // ─── DEPARTMENT USERS — one worker per production department (14 rows) ───
  // Covers all 14 production departments across the 4 trailer series (XP, Yeti,
  // Deck Over, Gooseneck/Dump). QC is intentionally a single inspector
  // (qc@bigfoot.dev above) who owns all 6 QC departments — not one per dept.
  // Same password as other dev accounts: Dev1234!
  //
  // Email format: <dept_code_lowercase>@bigfoot.dev
  // e.g. xp_jig@bigfoot.dev, paint_prep@bigfoot.dev
  const deptUserData: {
    deptCode: string;
    fullName: string;
    role: UserRole;
  }[] = [
    // XP series
    { deptCode: 'XP_JIG', fullName: 'XP Jig Welder', role: UserRole.worker },
    { deptCode: 'XP_FIN', fullName: 'XP Finish Welder', role: UserRole.worker },
    // Yeti series
    { deptCode: 'YETI_JIG', fullName: 'Yeti Jig Welder', role: UserRole.worker },
    { deptCode: 'YETI_FIN', fullName: 'Yeti Finish Welder', role: UserRole.worker },
    // Deck Over series
    { deptCode: 'DO_JIG', fullName: 'Deck Over Jig Welder', role: UserRole.worker },
    { deptCode: 'DO_FIN', fullName: 'Deck Over Finish Welder', role: UserRole.worker },
    // Gooseneck / Dump series
    { deptCode: 'GN_WELD', fullName: 'Gooseneck Jig Welder', role: UserRole.worker },
    { deptCode: 'GN_FIN', fullName: 'Gooseneck Finish Welder', role: UserRole.worker },
    // Shared production departments
    { deptCode: 'PAINT_PREP', fullName: 'Paint Prep Worker', role: UserRole.worker },
    { deptCode: 'PAINT_A', fullName: 'Paint Booth A Worker', role: UserRole.worker },
    { deptCode: 'PAINT_B', fullName: 'Paint Booth B Worker', role: UserRole.worker },
    { deptCode: 'HYDRAULICS', fullName: 'Hydraulics Technician', role: UserRole.worker },
    { deptCode: 'WIRE', fullName: 'Wire Technician', role: UserRole.worker },
    { deptCode: 'WOOD', fullName: 'Wood Installer', role: UserRole.worker },
  ];

  for (const u of deptUserData) {
    const dept = departments[u.deptCode];
    if (!dept) {
      throw new Error(`Department not found for user seed: ${u.deptCode}`);
    }
    const email = `${u.deptCode.toLowerCase()}@bigfoot.dev`;
    await prisma.user.upsert({
      where: { email },
      update: {
        passwordHash,
        fullName: u.fullName,
        role: u.role,
        primaryLocationId: factory.id,
        primaryDepartmentId: dept.id,
        isActive: true,
      },
      create: {
        email,
        fullName: u.fullName,
        passwordHash,
        role: u.role,
        primaryLocationId: factory.id,
        primaryDepartmentId: dept.id,
        isActive: true,
      },
    });
  }
  console.log(`✅ Department users seeded: ${deptUserData.length} (password: ${DEV_PASSWORD})`);

  console.log('\n🎉 Seed complete!');
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
