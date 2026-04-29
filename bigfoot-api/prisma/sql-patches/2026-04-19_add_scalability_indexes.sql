-- =============================================================================
-- SQL patch: add scalability indexes for Trailer + DeliveryBatch hot paths
-- Apply with:  psql "$DATABASE_URL" -f prisma/sql-patches/2026-04-19_add_scalability_indexes.sql
-- Idempotent (uses IF NOT EXISTS).
-- Uses CONCURRENTLY so it won't block reads/writes on large tables.
-- =============================================================================

-- Trailer indexes --------------------------------------------------------------
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_trailers_status_priority
  ON trailers (status, global_priority, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_trailers_customer_status
  ON trailers (customer_id, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_trailers_location_status
  ON trailers (current_location_id, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_trailers_hot_status
  ON trailers (is_hot, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_trailers_model
  ON trailers (trailer_model_id);

-- DeliveryBatch indexes --------------------------------------------------------
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_delivery_batches_status_created
  ON delivery_batches (status, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_delivery_batches_driver_status
  ON delivery_batches (driver_user_id, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_delivery_batches_creator
  ON delivery_batches (created_by_user_id, created_at DESC);
