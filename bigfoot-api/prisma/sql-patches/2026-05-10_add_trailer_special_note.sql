-- =============================================================================
-- Add special_note column to trailers
-- =============================================================================
-- Free-form short note that office/production staff can attach to a trailer
-- on top of the existing options_notes field. Distinct from options_notes so
-- that workshop "options/addons" remain searchable separately from one-off
-- handling notes (e.g. "ship empty", "hold for VIN check").
--
-- Idempotent: uses IF NOT EXISTS on the column.
-- Apply with:  psql "$DATABASE_URL" -f <path>
-- =============================================================================

ALTER TABLE trailers
  ADD COLUMN IF NOT EXISTS special_note VARCHAR(500);
