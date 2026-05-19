-- =============================================================================
-- Add contact_phone to deliveries
-- =============================================================================
-- A per-delivery contact number entered when the delivery is created. The
-- driver's "Text" action uses this number, falling back to the trailer
-- customer's phone when it is not set — so a delivery can be texted even when
-- the trailer has no customer record or a different on-site contact.
--
-- Idempotent: column add uses IF NOT EXISTS.
-- Apply with:  npx prisma db execute --file <path>
-- =============================================================================

ALTER TABLE deliveries
  ADD COLUMN IF NOT EXISTS contact_phone VARCHAR(20);
