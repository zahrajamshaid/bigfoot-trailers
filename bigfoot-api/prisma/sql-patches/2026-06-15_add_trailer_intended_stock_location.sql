-- =============================================================================
-- Trailers: intended_stock_location_id column
-- =============================================================================
-- Captures the destination yard a stock build is *intended* to ship to once
-- production completes. The trailer stays physically at the factory until a
-- stack_to_location delivery moves it. Without this column we'd have to either
-- abuse current_location_id (the old behavior — wrong because the trailer
-- isn't actually at the destination yet) or lose the intent entirely.
--
-- Nullable: customer trailers + Mulberry-destined stock builds both leave it
-- null. The trailer-create flow keeps current_location_id at the factory in
-- every case now.
--
-- Idempotent: column add + FK + index all guarded.
-- Apply with:  psql "$DATABASE_URL" -f <path>
-- =============================================================================

ALTER TABLE trailers
  ADD COLUMN IF NOT EXISTS intended_stock_location_id INT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_name = 'trailers_intended_stock_location_id_fkey'
      AND table_name = 'trailers'
  ) THEN
    ALTER TABLE trailers
      ADD CONSTRAINT trailers_intended_stock_location_id_fkey
      FOREIGN KEY (intended_stock_location_id) REFERENCES locations(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_trailers_intended_stock_location
  ON trailers (intended_stock_location_id);
