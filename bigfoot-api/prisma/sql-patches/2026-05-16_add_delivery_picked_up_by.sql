-- =============================================================================
-- Add picked_up_by_name to deliveries
-- =============================================================================
-- For factory-pickup deliveries, office/transport staff record the name of the
-- person who collected the trailer when they mark the pickup complete. Plain
-- free text — the collector is often not the billing customer.
--
-- Idempotent: column add uses IF NOT EXISTS.
-- Apply with:  npx prisma db execute --file <path>
-- =============================================================================

ALTER TABLE deliveries
  ADD COLUMN IF NOT EXISTS picked_up_by_name VARCHAR(200);
