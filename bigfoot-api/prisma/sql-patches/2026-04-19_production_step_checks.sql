-- Worker self-check results recorded at step completion.
-- Visible to the QC manager downstream for review.
CREATE TABLE IF NOT EXISTS production_step_checks (
  id                  BIGSERIAL PRIMARY KEY,
  production_step_id  BIGINT NOT NULL REFERENCES production_steps(id) ON DELETE CASCADE,
  checklist_item_id   INTEGER NOT NULL REFERENCES qc_checklist_items(id),
  passed              BOOLEAN NOT NULL,
  note                TEXT,
  checked_by_user_id  BIGINT NOT NULL REFERENCES users(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (production_step_id, checklist_item_id)
);

CREATE INDEX IF NOT EXISTS idx_production_step_checks_step
  ON production_step_checks (production_step_id);
