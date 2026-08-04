// =============================================================================
// Jig-queue starvation config — shared by the production service (dashboard
// board), the notifications service (alerts), and the background sweep so they
// can never disagree on which departments are jigs or where the thresholds sit.
//
// The four jig-weld departments are the START of every production line. When
// one runs low there is nothing left to weld and the whole line stalls, so we
// warn early (≤5) and escalate to critical (≤2). "Count" is always the number
// of active + waiting production steps sitting in that jig department.
// =============================================================================

export const JIG_CODES = ['XP_JIG', 'YETI_JIG', 'DO_JIG', 'GN_WELD'] as const;
export type JigCode = (typeof JIG_CODES)[number];

/** ≤ this (but above critical) → amber warning. */
export const JIG_WARN_THRESHOLD = 5;
/** ≤ this → red critical: the line is about to stop. */
export const JIG_CRITICAL_THRESHOLD = 2;

export type JigSeverity = 'ok' | 'warning' | 'critical';

export function jigSeverity(count: number): JigSeverity {
  if (count <= JIG_CRITICAL_THRESHOLD) return 'critical';
  if (count <= JIG_WARN_THRESHOLD) return 'warning';
  return 'ok';
}

/** True when a jig is a member of the jig set (accepts any string). */
export function isJigCode(code: string): code is JigCode {
  return (JIG_CODES as readonly string[]).includes(code);
}
