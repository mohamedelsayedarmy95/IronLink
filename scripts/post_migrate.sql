-- IronLink — table-level hardening applied AFTER Alembic migrations.
-- Runs on every container boot; every statement is idempotent.

-- audit_writer may only append to the audit log.
GRANT INSERT ON TABLE audit_logs TO audit_writer;

-- Prevent the application role from rewriting history even if application
-- code is buggy. (The table owner still bypasses RLS; api_user does not.)
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS audit_insert_only ON audit_logs;
CREATE POLICY audit_insert_only
  ON audit_logs
  FOR INSERT
  TO api_user, audit_writer
  WITH CHECK (true);

DROP POLICY IF EXISTS audit_select_all ON audit_logs;
CREATE POLICY audit_select_all
  ON audit_logs
  FOR SELECT
  USING (true);

-- A message must target exactly one of: a direct recipient or a group.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_message_target'
      AND conrelid = 'messages'::regclass
  ) THEN
    ALTER TABLE messages
      ADD CONSTRAINT chk_message_target
      CHECK (
        (recipient_id IS NOT NULL AND group_id IS NULL) OR
        (recipient_id IS NULL AND group_id IS NOT NULL)
      );
  END IF;
END
$$;
