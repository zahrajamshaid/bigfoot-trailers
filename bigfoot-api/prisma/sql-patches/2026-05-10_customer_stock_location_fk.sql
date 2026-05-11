-- =============================================================================
-- Customers ↔ Locations: stock_location_id FK
-- =============================================================================
-- Adds a nullable stock_location_id column to customers + an FK to locations.
-- Required when customer_type='stock_location' so the trailer-create flow can
-- auto-fill the stock destination chip when a stock customer is picked.
--
-- Idempotent: column add and FK add both guarded.
-- Apply with:  psql "$DATABASE_URL" -f <path>
-- =============================================================================

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS stock_location_id INT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_name = 'customers_stock_location_id_fkey'
      AND table_name = 'customers'
  ) THEN
    ALTER TABLE customers
      ADD CONSTRAINT customers_stock_location_id_fkey
      FOREIGN KEY (stock_location_id) REFERENCES locations(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_customers_stock_location
  ON customers (stock_location_id);

-- Best-effort backfill for the seeded stock customers (Mulberry Stock,
-- Tappahannock Stock, ...). Safe no-op if any name doesn't match a location.
UPDATE customers c
SET stock_location_id = l.id
FROM locations l
WHERE c.customer_type = 'stock_location'
  AND c.stock_location_id IS NULL
  AND l.city = TRIM(REPLACE(c.name, 'Stock', ''));
