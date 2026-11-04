CREATE OR REPLACE FUNCTION ironlink_maintenance.prune_audit_logs(requested_before timestamptz)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER STRICT
SET search_path = pg_catalog, pg_temp
SET row_security = off
AS $retention$
DECLARE
    deleted_count integer;
BEGIN
    IF {retention_days} <= 0 THEN
        RETURN 0;
    END IF;
    DELETE FROM public.audit_logs WHERE id IN (
        SELECT id FROM public.audit_logs
        WHERE created_at < LEAST(requested_before,
            statement_timestamp() - make_interval(days => {retention_days}))
        ORDER BY created_at, id
        LIMIT 1000
    );
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$retention$;
