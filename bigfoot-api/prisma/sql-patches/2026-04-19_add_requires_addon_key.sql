-- =============================================================================
-- Options-gated QC checklist items
-- =============================================================================
-- Adds a nullable `requires_addon_key` column to qc_checklist_items so that
-- checklist items can be conditionally included in the inspection based on
-- the trailer's selected options (trailer_addons.addon_name).
--
-- Semantics:
--   NULL → item is always shown for its (department, series) scope
--   '*'  → item is shown whenever the trailer has at least one addon
--   else → item is shown only when trailer_addons.addon_name matches
--
-- Idempotent: uses IF NOT EXISTS on both column and index.
-- Apply with:  psql "$DATABASE_URL" -f <path>
-- =============================================================================

ALTER TABLE qc_checklist_items
  ADD COLUMN IF NOT EXISTS requires_addon_key VARCHAR(60);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_qc_checklist_items_addon_key
  ON qc_checklist_items (requires_addon_key);
