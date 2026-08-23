-- 006_allow_host_role.sql
-- Host application approvals set profiles.role='host' but the CHECK
-- constraint from 003 only allows ('user','admin'). Extend it. Idempotent.
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_role_check') THEN
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check
      CHECK (role IN ('user', 'admin', 'host'));
  END IF;
END $$;
