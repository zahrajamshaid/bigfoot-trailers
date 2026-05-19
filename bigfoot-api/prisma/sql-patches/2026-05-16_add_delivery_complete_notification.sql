-- =============================================================================
-- Add 'delivery_complete' to notification_type_enum
-- =============================================================================
-- When a delivery is marked complete, every active transport_manager receives
-- a durable push notification (in addition to the live DELIVERY_COMPLETE
-- WebSocket event). That notification needs its own type so the notification
-- center can label and filter it.
--
-- Idempotent: ADD VALUE IF NOT EXISTS is a no-op when the value already exists.
-- Apply with:  psql "$DATABASE_URL" -f <path>
-- =============================================================================

ALTER TYPE notification_type_enum ADD VALUE IF NOT EXISTS 'delivery_complete';
