-- ============================================================================
-- 003_security_hardening.sql
-- Remediation of findings from the 2026-08-22 hard audit.
-- Run AFTER 001_init.sql and 002_functions.sql in the Supabase SQL editor.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Economy integrity constraints
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_coins_nonnegative') THEN
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_coins_nonnegative CHECK (coins >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_diamonds_nonnegative') THEN
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_diamonds_nonnegative CHECK (diamonds >= 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'gift_transactions_quantity_positive') THEN
    ALTER TABLE public.gift_transactions ADD CONSTRAINT gift_transactions_quantity_positive CHECK (quantity > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'gift_transactions_totals_nonnegative') THEN
    ALTER TABLE public.gift_transactions ADD CONSTRAINT gift_transactions_totals_nonnegative
      CHECK (total_coins >= 0 AND total_diamonds >= 0);
  END IF;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- 2) Canonical admin role model (single source of truth: profiles.role)
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'user';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_role_check') THEN
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('user', 'admin'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);

-- SECURITY DEFINER so it sees through RLS; stable within a statement.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- 3) Reports table: it previously had RLS enabled but ZERO policies, making
--    it unusable for clients and wide open only to the service key.
-- ---------------------------------------------------------------------------
CREATE POLICY "reports_insert_own"
  ON public.reports FOR INSERT TO authenticated
  WITH CHECK (reporter_id = auth.uid());

CREATE POLICY "reports_select_admin"
  ON public.reports FOR SELECT TO authenticated
  USING (public.is_admin() OR reporter_id = auth.uid());

CREATE POLICY "reports_update_admin"
  ON public.reports FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ---------------------------------------------------------------------------
-- 4) Lock down SECURITY DEFINER functions: no default PUBLIC execute.
--    Wallet RPCs are invoked by the API using the service-role key (which
--    bypasses RLS but still needs EXECUTE), so grant those to the service
--    role explicitly.
-- ---------------------------------------------------------------------------
DO $$
DECLARE fn RECORD;
BEGIN
  FOR fn IN
    SELECT p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.prosecdef
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I FROM PUBLIC', fn.proname);
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.deduct_coins(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.add_coins(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.deduct_diamonds(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.add_diamonds(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.increment_stream_likes(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.increment_post_comments(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_top_streamers(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_top_gifters(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 5) get_admin_dashboard_stats: previously SECURITY DEFINER with default
--    PUBLIC execute -> anonymous callers could read platform financials.
--    Re-created with an internal admin guard AND revoked from PUBLIC.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_admin_dashboard_stats()
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT json_build_object(
    'total_users', (SELECT COUNT(*) FROM public.profiles),
    'live_streams', (SELECT COUNT(*) FROM public.streams WHERE status = 'live'),
    'total_streams', (SELECT COUNT(*) FROM public.streams),
    'total_posts', (SELECT COUNT(*) FROM public.posts),
    'pending_reports', (SELECT COUNT(*) FROM public.reports WHERE status = 'pending'),
    'total_revenue', (SELECT COALESCE(SUM(amount), 0) FROM public.wallet_transactions WHERE type = 'purchase'),
    'total_gifts_sent', (SELECT COUNT(*) FROM public.gift_transactions),
    'coins_in_circulation', (SELECT COALESCE(SUM(coins), 0) FROM public.profiles),
    'diamonds_in_circulation', (SELECT COALESCE(SUM(diamonds), 0) FROM public.profiles)
  ) INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.get_admin_dashboard_stats() FROM PUBLIC;
