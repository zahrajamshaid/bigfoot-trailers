-- =============================================================================
-- Add 'purchasing' value to user_role_enum
-- =============================================================================
-- New read-only role for the purchasing team: sees the trailers list (overall
-- production) so they can see incoming orders and plan parts ordering.
--
-- Idempotent: ADD VALUE IF NOT EXISTS makes re-runs safe.
-- Apply with:  psql "$DATABASE_URL" -f <path>
-- =============================================================================

ALTER TYPE user_role_enum ADD VALUE IF NOT EXISTS 'purchasing';
