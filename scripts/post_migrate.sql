-- IronLink — table-level hardening applied AFTER Alembic migrations.
-- Runs on every container boot; every statement is idempotent.

-- The runtime identifier is quoted by database_bootstrap, never interpolated
-- from an environment variable. No role is assumed or created by this file.
-- Runtime is verified to be independent of the table owner before startup.
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS audit_insert_only ON public.audit_logs;
CREATE POLICY audit_insert_only
  ON public.audit_logs
  FOR INSERT
  TO {runtime}
  WITH CHECK (true);

DROP POLICY IF EXISTS audit_select_all ON public.audit_logs;
CREATE POLICY audit_select_all
  ON public.audit_logs
  FOR SELECT
  TO {runtime}
  USING (true);

-- A message must target exactly one of: a direct recipient or a group.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_message_target'
      AND conrelid = 'public.messages'::regclass
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT chk_message_target
      CHECK (
        (recipient_id IS NOT NULL AND group_id IS NULL) OR
        (recipient_id IS NULL AND group_id IS NOT NULL)
      );
  END IF;
END
$$;
