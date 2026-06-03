-- =============================================================================
-- Add scheduled_date to deliveries
-- =============================================================================
-- The date a delivery is planned for. Sales picks it when creating the
-- delivery so the transport manager can see what's coming on their portal
-- without having to ask. Nullable for backwards-compat with rows created
-- before the column existed and for factory_pickup deliveries (recorded as
-- already-completed in one step — the "scheduled" concept doesn't apply).
--
-- Idempotent: column add uses IF NOT EXISTS.
-- Apply with:  npx prisma db execute --file <path>
-- =============================================================================

ALTER TABLE deliveries
  ADD COLUMN IF NOT EXISTS scheduled_date DATE;

CREATE INDEX IF NOT EXISTS idx_deliveries_scheduled_date
  ON deliveries (scheduled_date)
  WHERE scheduled_date IS NOT NULL;
