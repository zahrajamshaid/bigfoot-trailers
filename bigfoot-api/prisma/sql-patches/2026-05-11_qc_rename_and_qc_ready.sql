-- =============================================================================
-- QC department renames + qc_ready notification type
-- =============================================================================
-- 1. Add qc_ready value to the notification_type_enum so the push service can
--    persist push_notifications rows for that event.
-- 2. Rename the generic "Quality Control N" department display names to the
--    actual production stage they're inspecting. Codes (QC_1..QC_5, FINAL_QC)
--    stay the same so existing FK references and saved checklists don't break.
--
-- Idempotent: enum add uses IF NOT EXISTS, UPDATEs are safe to re-run.
-- Apply with:  psql "$DATABASE_URL" -f <path>
-- =============================================================================

ALTER TYPE notification_type_enum ADD VALUE IF NOT EXISTS 'qc_ready';

UPDATE departments SET display_name = 'Jig Weld QC'              WHERE code = 'QC_1';
UPDATE departments SET display_name = 'Finish Weld QC'           WHERE code = 'QC_2';
UPDATE departments SET display_name = 'Paint Prep QC'            WHERE code = 'QC_3';
UPDATE departments SET display_name = 'Paint QC'                 WHERE code = 'QC_4';
UPDATE departments SET display_name = 'Wire / Hydraulics QC'     WHERE code = 'QC_5';
UPDATE departments SET display_name = 'Final QC'                 WHERE code = 'FINAL_QC';
