-- Run only via script/p03_apply_audit_lockdown.sh as PostgreSQL superuser.
-- Safe to reapply. No change to canonical development DB.
BEGIN;
DO $$
BEGIN
  IF current_database() <> 'rails8_p03_sandbox' OR current_user <> 'postgres' THEN
    RAISE EXCEPTION 'wrong database or role for P0.3 audit lockdown';
  END IF;
END;
$$;
ALTER TABLE public.platform_security_events OWNER TO rails8_p03_audit_owner;
ALTER TABLE public.platform_audit_events OWNER TO rails8_p03_audit_owner;
ALTER FUNCTION public.p03_reject_audit_mutation() OWNER TO rails8_p03_audit_owner;
ALTER SEQUENCE public.platform_security_events_id_seq OWNER TO rails8_p03_audit_owner;
ALTER SEQUENCE public.platform_audit_events_id_seq OWNER TO rails8_p03_audit_owner;
REVOKE ALL ON public.platform_security_events FROM rails8_p03_operator;
REVOKE ALL ON public.platform_audit_events FROM rails8_p03_operator;
REVOKE ALL ON SEQUENCE public.platform_security_events_id_seq FROM rails8_p03_operator;
REVOKE ALL ON SEQUENCE public.platform_audit_events_id_seq FROM rails8_p03_operator;
GRANT SELECT,INSERT ON public.platform_security_events TO rails8_p03_operator;
GRANT SELECT,INSERT ON public.platform_audit_events TO rails8_p03_operator;
GRANT USAGE,SELECT ON SEQUENCE public.platform_security_events_id_seq TO rails8_p03_operator;
GRANT USAGE,SELECT ON SEQUENCE public.platform_audit_events_id_seq TO rails8_p03_operator;
COMMIT;
