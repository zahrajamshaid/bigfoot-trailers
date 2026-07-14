/**
 * Turns raw audit rows into plain English.
 *
 * The old behaviour only diffed five hard-coded fields and fell back to the
 * bare verb for everything else — which is why the trailer history was a wall
 * of "Updated" with no way to tell what actually happened. This module answers
 * the four questions a human asks of a history row:
 *
 *     WHO did it · WHAT happened · WHEN · WHAT CHANGED (from → to)
 *
 * It is deliberately dumb about the database: callers pass a `Lookups` bag so
 * ids can be rendered as names (location 3 → "Mulberry") without this module
 * needing Prisma.
 */

/** One field that changed, rendered for a human. */
export interface FieldChange {
  /** Human label, e.g. "Sale status". */
  field: string;
  /** Human value before, e.g. "Available". Null when the field was unset. */
  from: string | null;
  /** Human value after. */
  to: string | null;
}

/** Optional id → name maps so we can print names instead of raw ids. */
export interface Lookups {
  locations?: Map<number, string>;
  departments?: Map<number, string>;
  users?: Map<string, string>;
  customers?: Map<string, string>;
  models?: Map<number, string>;
}

/**
 * Fields that carry no meaning for a reader. `updatedAt` changes on every
 * write, ids never "change" in a useful sense, and internal sync bookkeeping
 * is noise on a shop-floor history.
 */
const NOISE = new Set([
  'id',
  'createdAt',
  'updatedAt',
  'created_at',
  'updated_at',
  'qbSyncError',
  'syncError',
  'qbLastSyncedAt',
]);

/** camelCase / snake_case → "Sentence case" label, with explicit overrides. */
const FIELD_LABELS: Record<string, string> = {
  soNumber: 'SO number',
  vinNumber: 'VIN',
  trailerModelId: 'Model',
  customerId: 'Customer',
  currentLocationId: 'Location',
  intendedStockLocationId: 'Destination yard',
  stockLocationId: 'Destination yard',
  globalPriority: 'Priority',
  isHot: 'Hot',
  isStockBuild: 'Stock build',
  saleStatus: 'Sale status',
  soldToName: 'Sold to',
  soldAt: 'Sold on',
  optionsNotes: 'Build notes',
  specialNote: 'VIN number',
  sizeFt: 'Size (ft)',
  departmentId: 'Department',
  completedByUserId: 'Completed by',
  qbSoPdfStorageKey: 'Attached PDF',
  customerLocked: 'Customer locked',
};

/** Values that read better than the raw enum. */
const VALUE_LABELS: Record<string, string> = {
  ready_for_delivery: 'Ready for delivery',
  pending_production: 'Pending production',
  in_production: 'In production',
  sale_pending: 'Sale pending',
};

/** A nested relation object/array — never meaningful in a field diff. */
function isRelation(v: unknown): boolean {
  return typeof v === 'object' && v !== null && !(v instanceof Date);
}

/** Turn an action string into a verb a person recognises. */
export function humanAction(action: string): string {
  const map: Record<string, string> = {
    'trailer.jumped_to_step': 'Jumped to step',
    'trailer.priority_set': 'Priority changed',
    'trailer.hot_toggled': 'Hot flag toggled',
    'qc.passed': 'QC passed',
    'qc.failed': 'QC failed',
    'sales_order.approved': 'Sales Order approved',
    'sales_order.converted': 'Converted to Sales Order',
  };
  if (map[action]) return map[action];

  const upper = action.toUpperCase();
  if (upper === 'CREATE') return 'Created';
  if (upper === 'UPDATE') return 'Updated';
  if (upper === 'DELETE') return 'Deleted';

  return action
    .replace(/[._]+/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

/** Human label for a field key. */
export function fieldLabel(key: string): string {
  if (FIELD_LABELS[key]) return FIELD_LABELS[key];
  const spaced = key
    .replace(/_/g, ' ')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .toLowerCase()
    .trim();
  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}

/** Human rendering of a single value, resolving ids to names when we can. */
export function formatValue(
  key: string,
  value: unknown,
  lookups: Lookups = {},
): string | null {
  if (value === null || value === undefined || value === '') return null;

  // Ids → names.
  if (key === 'currentLocationId' || key === 'intendedStockLocationId' || key === 'stockLocationId') {
    const n = lookups.locations?.get(Number(value));
    return n ?? `Location #${String(value)}`;
  }
  if (key === 'departmentId') {
    const n = lookups.departments?.get(Number(value));
    return n ?? `Dept #${String(value)}`;
  }
  if (key === 'trailerModelId') {
    const n = lookups.models?.get(Number(value));
    return n ?? `Model #${String(value)}`;
  }
  if (key === 'customerId') {
    const n = lookups.customers?.get(String(value));
    return n ?? `Customer #${String(value)}`;
  }
  if (key.endsWith('UserId') || key === 'userId') {
    const n = lookups.users?.get(String(value));
    return n ?? `User #${String(value)}`;
  }

  if (typeof value === 'boolean') return value ? 'Yes' : 'No';

  if (typeof value === 'number') {
    // 9999 is the "no priority" sentinel — saying "9999" helps nobody.
    if (key === 'globalPriority' && value >= 9999) return 'Normal';
    return String(value);
  }

  const s = String(value);
  if (VALUE_LABELS[s]) return VALUE_LABELS[s];

  // Single-word enums (sold, available, delivered) — title-case them so a
  // status never reads like a database value.
  if (/Status$/.test(key) || key === 'status' || key === 'result') {
    if (/^[a-z]+$/.test(s)) return s.charAt(0).toUpperCase() + s.slice(1);
  }

  // ISO timestamps → readable date.
  if (/^\d{4}-\d{2}-\d{2}T/.test(s)) {
    const d = new Date(s);
    if (!Number.isNaN(d.getTime())) {
      return d.toISOString().slice(0, 10);
    }
  }

  // snake_case enums → Sentence case.
  if (/^[a-z0-9]+(_[a-z0-9]+)+$/.test(s)) {
    const t = s.replace(/_/g, ' ');
    return t.charAt(0).toUpperCase() + t.slice(1);
  }
  return s;
}

/**
 * Every field that actually changed, rendered from → to. Unlike the old
 * five-field allow-list this reports ANY meaningful change, which is the
 * whole point — "we can't tell what happened" was caused by silently
 * dropping fields.
 */
export function diffFields(
  oldValues: unknown,
  newValues: unknown,
  lookups: Lookups = {},
): FieldChange[] {
  const oldV = (oldValues ?? null) as Record<string, unknown> | null;
  const newV = (newValues ?? null) as Record<string, unknown> | null;
  if (!newV) return [];

  const keys = new Set([...Object.keys(oldV ?? {}), ...Object.keys(newV)]);
  const changes: FieldChange[] = [];

  for (const key of keys) {
    if (NOISE.has(key)) continue;
    const before = oldV ? oldV[key] : undefined;
    const after = newV[key];

    // Relation objects / arrays (customer, trailerModel, addons) render as
    // "[object Object]" and duplicate the *Id field that already carries the
    // meaning. Skip them — the id fields are resolved to names instead.
    if (isRelation(after) || isRelation(before)) continue;
    // A create has no old values — report what it was set to.
    if (oldV && before === undefined) continue;
    if (after === undefined) continue;
    if (JSON.stringify(before ?? null) === JSON.stringify(after ?? null)) continue;

    changes.push({
      field: fieldLabel(key),
      from: oldV ? formatValue(key, before, lookups) : null,
      to: formatValue(key, after, lookups),
    });
  }
  return changes;
}

/**
 * One-line plain-English summary. Prefers the concrete change ("Status: In
 * production → Ready for delivery") over the bare verb, and only falls back
 * to the verb when there is genuinely nothing else to say.
 */
export function summarize(
  action: string,
  entityType: string,
  oldValues: unknown,
  newValues: unknown,
  changes: FieldChange[],
): string {
  const verb = humanAction(action);
  const newV = (newValues ?? null) as Record<string, unknown> | null;

  // QC rows always "create" — the verb tells you nothing; the result does.
  if (entityType === 'qc_inspection' && newV) {
    const result = String(newV.result ?? '').toLowerCase();
    const attempt = newV.attemptNumber ?? newV.attempt_number;
    const rework =
      newV.reworkTargetDeptCode ?? newV.reworkTargetDept ?? newV.reworkSentToDeptCode;
    if (result === 'pass') return attempt ? `QC passed (attempt ${attempt})` : 'QC passed';
    if (result === 'fail') {
      const base = attempt ? `QC failed (attempt ${attempt})` : 'QC failed';
      return rework ? `${base} — sent back to ${String(rework)}` : base;
    }
  }

  if (changes.length === 0) return verb;

  const render = (c: FieldChange) =>
    c.from === null
      ? `${c.field} set to ${c.to ?? 'none'}`
      : `${c.field}: ${c.from} → ${c.to ?? 'none'}`;

  // Two or fewer: spell them out. More: lead with the first, count the rest —
  // the full list still travels in `changes` for the UI to expand.
  if (changes.length <= 2) return changes.map(render).join(', ');
  return `${render(changes[0])} (+${changes.length - 1} more changes)`;
}
