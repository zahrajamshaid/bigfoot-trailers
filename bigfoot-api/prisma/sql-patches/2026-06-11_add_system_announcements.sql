-- =============================================================================
-- Add system_announcements + system_announcement_acks
-- =============================================================================
-- Owner/production-manager pushes a floor-wide message; each user has to tap
-- OK in the app modal before they can keep using it. The ack table records
-- exactly who acknowledged each message.
--
-- Idempotent: every CREATE uses IF NOT EXISTS.
-- =============================================================================

CREATE TABLE IF NOT EXISTS system_announcements (
  id                BIGSERIAL PRIMARY KEY,
  title             VARCHAR(120),
  body              TEXT        NOT NULL,
  posted_by_user_id BIGINT      NOT NULL REFERENCES users(id),
  is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
  expires_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_announcements_active_oldest
  ON system_announcements (is_active, created_at);

CREATE TABLE IF NOT EXISTS system_announcement_acks (
  id              BIGSERIAL PRIMARY KEY,
  announcement_id BIGINT      NOT NULL REFERENCES system_announcements(id) ON DELETE CASCADE,
  user_id         BIGINT      NOT NULL REFERENCES users(id),
  acked_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_announcement_ack_per_user
  ON system_announcement_acks (announcement_id, user_id);

CREATE INDEX IF NOT EXISTS idx_announcement_acks_user
  ON system_announcement_acks (user_id, acked_at DESC);
