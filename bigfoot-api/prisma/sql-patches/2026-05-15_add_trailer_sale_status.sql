-- =============================================================================
-- Add sale_status to trailers
-- =============================================================================
-- Sale state tracked separately from the production `status`. A trailer is
-- either still 'available' (a stock build / no customer yet), 'sale_pending'
-- (a deal in progress), or 'sold' (a buyer is committed). Any trailer linked
-- to a customer is treated as sold — see the backfill below.
--
-- Only owner / sales / production_manager change this via
-- PATCH /trailers/:id/sale-status.
--
-- Idempotent: enum create is guarded, column add uses IF NOT EXISTS.
-- Apply with:  psql "$DATABASE_URL" -f <path>
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'trailer_sale_status_enum') THEN
    CREATE TYPE trailer_sale_status_enum AS ENUM ('available', 'sale_pending', 'sold');
  END IF;
END $$;

ALTER TABLE trailers
  ADD COLUMN IF NOT EXISTS sale_status trailer_sale_status_enum NOT NULL DEFAULT 'available';

-- Free-text buyer name recorded when a stock / no-customer trailer is sold.
-- Plain text by design — customer records move to the GoHighLevel integration.
ALTER TABLE trailers
  ADD COLUMN IF NOT EXISTS sold_to_name VARCHAR(200);

-- Backfill: a trailer already attached to a customer is, by definition, sold.
UPDATE trailers
SET sale_status = 'sold'
WHERE customer_id IS NOT NULL
  AND sale_status = 'available';

CREATE INDEX IF NOT EXISTS idx_trailers_sale_status
  ON trailers (sale_status);
