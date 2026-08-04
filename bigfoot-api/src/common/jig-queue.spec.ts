import {
  jigSeverity,
  isJigCode,
  JIG_CODES,
  JIG_WARN_THRESHOLD,
  JIG_CRITICAL_THRESHOLD,
} from './jig-queue';

describe('jig-queue config', () => {
  it('thresholds are two-tier: critical below warning', () => {
    expect(JIG_CRITICAL_THRESHOLD).toBeLessThan(JIG_WARN_THRESHOLD);
    expect(JIG_CRITICAL_THRESHOLD).toBe(2);
    expect(JIG_WARN_THRESHOLD).toBe(3);
  });

  it('jigSeverity classifies counts into ok / warning / critical', () => {
    expect(jigSeverity(0)).toBe('critical');
    expect(jigSeverity(2)).toBe('critical'); // ≤2
    expect(jigSeverity(3)).toBe('warning'); // ≤3
    expect(jigSeverity(4)).toBe('ok');
    expect(jigSeverity(50)).toBe('ok');
  });

  it('isJigCode recognises the four jig-weld departments only', () => {
    for (const code of JIG_CODES) expect(isJigCode(code)).toBe(true);
    expect(isJigCode('PAINT_A')).toBe(false);
    expect(isJigCode('FINAL_QC')).toBe(false);
    expect(isJigCode('')).toBe(false);
  });
});
