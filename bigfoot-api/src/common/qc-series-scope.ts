import { QcSeriesScope, TrailerSeries } from '@prisma/client';

/**
 * Map a trailer's series onto the QC checklist scope it should be graded with.
 *
 * `TrailerSeries` and `QcSeriesScope` are NOT the same enum. Series added after
 * the QC scopes were defined (gooseneck_yeti, cxp) have no scope of their own —
 * they run the gooseneck production line 1-for-1, so they're inspected with the
 * gooseneck_dump checks.
 *
 * Getting this wrong is not cosmetic: callers used to cast the series straight
 * into the scope filter (`series as unknown as QcSeriesScope`). For a CXP
 * trailer that put an invalid enum value into the query, so the scope filter
 * was dropped and EVERY series' checks came back — the QC checklist rendered
 * each item once per scope (e.g. 18 labels × 4 scopes = 72 rows, each check
 * shown 4×). Always map through here; never cast.
 *
 * Returns null for series with no line-scoped checks (inventory), meaning
 * "don't constrain by series".
 */
export function toQcSeriesScope(series: TrailerSeries): QcSeriesScope | null {
  switch (series) {
    case TrailerSeries.xp:
      return QcSeriesScope.xp;
    case TrailerSeries.yeti:
      return QcSeriesScope.yeti;
    case TrailerSeries.deck_over:
      return QcSeriesScope.deck_over;
    case TrailerSeries.gooseneck_dump:
      return QcSeriesScope.gooseneck_dump;
    // Share the gooseneck line → share its QC checks.
    case TrailerSeries.gooseneck_yeti:
    case TrailerSeries.cxp:
      return QcSeriesScope.gooseneck_dump;
    // Inventory trailers are never built on a line.
    default:
      return null;
  }
}
