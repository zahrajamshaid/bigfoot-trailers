/**
 * SpecAttributes — the structured trailer spec that replaces the typed
 * paragraph in QuickBooks.
 *
 * This is the heart of Phase 2's "turn the spec into data" move: instead of a
 * human typing the description block into QBO, the configurator stores it as
 * fields and `renderSpecDescription()` composes the exact line-1 description
 * text QuickBooks prints on the Sales Order / Packing Slip.
 *
 * The label order + wording is calibrated to Bigfoot's real documents
 * (samples SO #6696 15ET20TLT and #6785 14DO24FLT). Any field left empty is
 * skipped so partial specs still render cleanly.
 */
export interface SpecAttributes {
  /** The type/model code printed on line 1, e.g. "15TLT20". */
  typeModel: string;
  /** e.g. "16' TILT DECK 4' STATIONARY" */
  length?: string;
  /** e.g. `83" BETWEEN FENDERS` */
  deckWidth?: string;
  /** e.g. "14,900LBS" */
  gvwr?: string;
  /** e.g. "11,500LBS" */
  payload?: string;
  /**
   * Frame lines. Rendered as `FRAME: <first>` then each remaining entry on
   * its own line (matching the multi-line FRAME block in the samples).
   */
  frame?: string[];
  /** e.g. "7K TORSION-TORFLEX 10 YEAR WARRANTY" (printed under "DEXTER AXLES"). */
  axles?: string;
  /** e.g. "235/80R16 14PLY" */
  tires?: string;
  /** e.g. "11GA FENDERS, 6 D RINGS, FULL RUB RAIL, TONGUE TOOL BOX" */
  standardOptions?: string;
  /** e.g. "ADJUSTABLE DEMCO EZ LATCH" */
  coupler?: string;
  /** e.g. "12K BULLDOG SPRING LOADED LEG" */
  jack?: string;
  /** e.g. "WATERTIGHT PLUG N PLAY AUTOMOTIVE HARNESS ..." */
  wiring?: string;
  /** e.g. "2 PART EPOXY PRIMER WITH 2 PART URETHANE TOPCOAT" */
  paint?: string;
  /** Any extra labeled lines to append verbatim (already "LABEL: value"). */
  extraLines?: string[];
}

/**
 * Merge an option's partial spec overrides onto a base spec. Options that
 * change the spec (e.g. a bigger axle package) carry a `specOverrides` object;
 * everything present on the override replaces the base. `frame`/`extraLines`
 * arrays replace wholesale when provided (options rarely touch them).
 */
export function mergeSpec(
  base: SpecAttributes,
  overrides?: Partial<SpecAttributes> | null,
): SpecAttributes {
  if (!overrides) return base;
  return { ...base, ...stripUndefined(overrides) };
}

function stripUndefined<T extends object>(o: T): Partial<T> {
  const out: Partial<T> = {};
  for (const [k, v] of Object.entries(o)) {
    if (v !== undefined && v !== null) (out as Record<string, unknown>)[k] = v;
  }
  return out;
}

/**
 * Render the SpecAttributes into the multi-line description string that goes
 * into the line-1 QBO estimate item description — matching the Bigfoot
 * Sales Order / Packing Slip format exactly.
 */
export function renderSpecDescription(spec: SpecAttributes): string {
  const lines: string[] = [];
  lines.push(`TYPE/MODEL: ${spec.typeModel}`);
  if (spec.length) lines.push(`LENGTH: ${spec.length}`);
  if (spec.deckWidth) lines.push(`DECK WIDTH: ${spec.deckWidth}`);
  if (spec.gvwr) lines.push(`GVWR: ${spec.gvwr}`);
  if (spec.payload) lines.push(`RECOMMENDED PAYLOAD: ${spec.payload}`);
  if (spec.frame && spec.frame.length > 0) {
    lines.push(`FRAME: ${spec.frame[0]}`);
    for (let i = 1; i < spec.frame.length; i++) lines.push(spec.frame[i]);
  }
  if (spec.axles) lines.push(`DEXTER AXLES: ${spec.axles}`);
  if (spec.tires) lines.push(`TIRES: ${spec.tires}`);
  if (spec.standardOptions) lines.push(`STANDARD OPTIONS: ${spec.standardOptions}`);
  if (spec.coupler) lines.push(`COUPLER: ${spec.coupler}`);
  if (spec.jack) lines.push(`JACK: ${spec.jack}`);
  if (spec.wiring) lines.push(`WIRING: ${spec.wiring}`);
  if (spec.paint) lines.push(`PAINT: ${spec.paint}`);
  if (spec.extraLines) lines.push(...spec.extraLines);
  return lines.join('\n');
}

/** Narrow an untyped JSON blob (TrailerModel.spec) into SpecAttributes. */
export function parseSpec(json: unknown): SpecAttributes | null {
  if (!json || typeof json !== 'object') return null;
  const o = json as Record<string, unknown>;
  if (typeof o['typeModel'] !== 'string') return null;
  return o as unknown as SpecAttributes;
}
