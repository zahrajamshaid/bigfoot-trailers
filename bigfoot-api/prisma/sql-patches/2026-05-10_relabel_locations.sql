-- =============================================================================
-- Relabel + reshape stock locations
-- =============================================================================
-- 1. Adds a short_label column so chip-style pickers in the apps can show
--    compact codes (Mul, Jax, VA, GA, TAL).
-- 2. Renames the Ashland location row in place (id stays the same so all
--    existing trailer/delivery FKs remain valid) — Bigfoot's VA yard moved
--    from Ashland to Tappahannock.
-- 3. Renames the matching "Ashland Stock" customer to "Tappahannock Stock"
--    so customers.service.stockCityFromCustomerName() still resolves to the
--    renamed location.
-- 4. Inserts a new Tallahassee FL location + matching stock customer.
--
-- Idempotent: every step uses IF NOT EXISTS / WHERE-guards so re-running the
-- patch on an already-migrated DB is a no-op.
-- Apply with:  psql "$DATABASE_URL" -f <path>
-- =============================================================================

-- 1. short_label column ------------------------------------------------------
ALTER TABLE locations
  ADD COLUMN IF NOT EXISTS short_label VARCHAR(8);

-- 2. Backfill labels on the existing rows ------------------------------------
UPDATE locations SET short_label = 'Mul'
  WHERE code = 'MULBERRY' AND (short_label IS NULL OR short_label <> 'Mul');

UPDATE locations SET short_label = 'Jax'
  WHERE code = 'JACKSONVILLE' AND (short_label IS NULL OR short_label <> 'Jax');

UPDATE locations SET short_label = 'GA'
  WHERE code = 'ATLANTA' AND (short_label IS NULL OR short_label <> 'GA');

-- 3. Rename Ashland → Tappahannock (preserves id and all FKs) ----------------
UPDATE locations
SET code        = 'TAPPAHANNOCK',
    name        = 'Bigfoot Trailers Tappahannock',
    city        = 'Tappahannock',
    state       = 'VA',
    short_label = 'VA'
WHERE code = 'ASHLAND';

-- 4. Rename the matching stock customer --------------------------------------
UPDATE customers
SET name = 'Tappahannock Stock'
WHERE name = 'Ashland Stock'
  AND customer_type = 'stock_location';

-- 5. New Tallahassee FL location ---------------------------------------------
INSERT INTO locations (code, name, city, state, is_factory, is_active, short_label)
SELECT 'TALLAHASSEE', 'Bigfoot Trailers Tallahassee', 'Tallahassee', 'FL', false, true, 'TAL'
WHERE NOT EXISTS (SELECT 1 FROM locations WHERE code = 'TALLAHASSEE');

-- 6. New Tallahassee stock customer ------------------------------------------
INSERT INTO customers (name, customer_type, sms_opt_out)
SELECT 'Tallahassee Stock', 'stock_location', true
WHERE NOT EXISTS (
  SELECT 1 FROM customers
  WHERE name = 'Tallahassee Stock' AND customer_type = 'stock_location'
);
