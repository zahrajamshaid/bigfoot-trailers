import {
  SpecAttributes,
  renderSpecDescription,
  mergeSpec,
  parseSpec,
} from './spec-attributes';

/**
 * The renderer must reproduce the exact line-1 description block that appears
 * on Bigfoot's real documents. This fixture is transcribed from sample
 * SO #6696 (15ET20TLT) — the packing slip in the repo root.
 */
describe('renderSpecDescription', () => {
  const yeti15: SpecAttributes = {
    typeModel: '15TLT20',
    length: "16' TILT DECK 4' STATIONARY",
    deckWidth: '83" BETWEEN FENDERS',
    gvwr: '14,900LBS',
    payload: '11,500LBS',
    frame: [
      '8" STRUCTURAL I BEAM - INTEGRATED TONGUE',
      '3" STRUCTURAL CHANNEL CROSSMEMBERS',
    ],
    axles: '7K TORSION-TORFLEX 10 YEAR WARRANTY',
    tires: '235/80R16 14PLY',
    standardOptions: '11GA FENDERS, 6 D RINGS, FULL RUB RAIL, TONGUE TOOL BOX',
    coupler: 'ADJUSTABLE DEMCO EZ LATCH',
    jack: '12K BULLDOG SPRING LOADED LEG',
    wiring:
      'WATERTIGHT PLUG N PLAY AUTOMOTIVE HARNESS WITH FLOW CHARGER BUILT IN. PAIRED WITH ALL LED LIGHTING',
    paint: '2 PART EPOXY PRIMER WITH 2 PART URETHANE TOPCOAT',
  };

  it('reproduces the SO #6696 15ET20TLT description block line-for-line', () => {
    const expected = [
      'TYPE/MODEL: 15TLT20',
      "LENGTH: 16' TILT DECK 4' STATIONARY",
      'DECK WIDTH: 83" BETWEEN FENDERS',
      'GVWR: 14,900LBS',
      'RECOMMENDED PAYLOAD: 11,500LBS',
      'FRAME: 8" STRUCTURAL I BEAM - INTEGRATED TONGUE',
      '3" STRUCTURAL CHANNEL CROSSMEMBERS',
      'DEXTER AXLES: 7K TORSION-TORFLEX 10 YEAR WARRANTY',
      'TIRES: 235/80R16 14PLY',
      'STANDARD OPTIONS: 11GA FENDERS, 6 D RINGS, FULL RUB RAIL, TONGUE TOOL BOX',
      'COUPLER: ADJUSTABLE DEMCO EZ LATCH',
      'JACK: 12K BULLDOG SPRING LOADED LEG',
      'WIRING: WATERTIGHT PLUG N PLAY AUTOMOTIVE HARNESS WITH FLOW CHARGER BUILT IN. PAIRED WITH ALL LED LIGHTING',
      'PAINT: 2 PART EPOXY PRIMER WITH 2 PART URETHANE TOPCOAT',
    ].join('\n');

    expect(renderSpecDescription(yeti15)).toBe(expected);
  });

  it('skips empty fields so a partial spec still renders cleanly', () => {
    const partial: SpecAttributes = { typeModel: '10ET18', gvwr: '10,000LBS' };
    expect(renderSpecDescription(partial)).toBe(
      'TYPE/MODEL: 10ET18\nGVWR: 10,000LBS',
    );
  });

  it('merges option spec overrides onto the base', () => {
    const merged = mergeSpec(yeti15, {
      tires: '235/85R16 14PLY',
      axles: '8K TORSION',
    });
    expect(merged.tires).toBe('235/85R16 14PLY');
    expect(merged.axles).toBe('8K TORSION');
    // untouched fields survive
    expect(merged.coupler).toBe('ADJUSTABLE DEMCO EZ LATCH');
  });

  it('ignores undefined/null override fields', () => {
    const merged = mergeSpec(yeti15, { tires: undefined, jack: null as never });
    expect(merged.tires).toBe('235/80R16 14PLY'); // base preserved
    expect(merged.jack).toBe('12K BULLDOG SPRING LOADED LEG');
  });

  it('parses a JSON spec blob and rejects a malformed one', () => {
    expect(parseSpec({ typeModel: '15TLT20' })?.typeModel).toBe('15TLT20');
    expect(parseSpec({ nope: true })).toBeNull();
    expect(parseSpec(null)).toBeNull();
  });
});
