-- =====================================================================
-- 009_reseller_scoped_approval.sql — Reseller Dashboard backend
-- Allows ACTIVE RESELLERS to approve/reject recharge requests that
-- reference THEIR OWN reseller_agents.id. Full admins keep unrestricted
-- access; the ownership check only applies to reseller-role callers.
--
-- IDEMPOTENT (safe to run multiple times). Do NOT modify 001–008.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. approve_recharge_request v3 — admin (unrestricted) OR the reseller
--    who owns the request's reseller_id.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.approve_recharge_request(UUID, UUID);
CREATE OR REPLACE FUNCTION public.approve_recharge_request(p_request_id UUID, p_actor UUID)
RETURNS VOID AS $$
DECLARE
  v_req public.recharge_requests;
  v_reseller public.reseller_agents;
  v_user_balance INTEGER;
  v_credit_balance BIGINT;
  v_admin_code TEXT;
  v_is_admin BOOLEAN;
  v_own_agent_id UUID;
  v_actor_type TEXT;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_actor AND role = 'admin'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    -- Reseller path: caller must own an active agent row and that row must
    -- be exactly the one the request was submitted to.
    SELECT id INTO v_own_agent_id
      FROM public.reseller_agents
     WHERE user_id = p_actor AND is_active
     LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Only admins or active resellers can approve recharge requests';
    END IF;
  END IF;

  SELECT * INTO v_req FROM public.recharge_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;
  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'Request already processed'; END IF;

  IF NOT v_is_admin THEN
    IF v_req.reseller_id IS NULL OR v_req.reseller_id <> v_own_agent_id THEN
      RAISE EXCEPTION 'You can only manage requests submitted to your own reseller code';
    END IF;
  END IF;

  SELECT * INTO v_reseller FROM public.reseller_agents WHERE id = v_req.reseller_id FOR UPDATE;
  IF NOT FOUND OR NOT v_reseller.is_active THEN RAISE EXCEPTION 'Reseller not available'; END IF;
  IF v_reseller.diamond_credit_balance < v_req.diamonds_requested THEN
    RAISE EXCEPTION 'Reseller has insufficient diamond credit';
  END IF;

  v_actor_type := CASE WHEN v_is_admin THEN 'admin' ELSE 'reseller' END;
  SELECT admin_code INTO v_admin_code FROM public.profiles WHERE id = p_actor;

  -- Side 1: credit the requester.
  UPDATE public.profiles SET diamonds = diamonds + v_req.diamonds_requested
   WHERE id = v_req.requester_id
  RETURNING diamonds INTO v_user_balance;
  INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                    actor_type, actor_id, reference_id, note)
  VALUES (v_req.requester_id, v_req.diamonds_requested, 'diamonds', v_user_balance, 'reseller_recharge',
          v_actor_type, p_actor, v_req.id,
          'via reseller ' || COALESCE(v_reseller.reseller_code, v_req.reseller_id::TEXT)
          || ', approved by ' || COALESCE(v_admin_code, left(p_actor::TEXT, 8)));

  -- Side 2: debit the reseller's credit stock.
  UPDATE public.reseller_agents SET diamond_credit_balance = diamond_credit_balance - v_req.diamonds_requested
   WHERE id = v_reseller.id
  RETURNING diamond_credit_balance INTO v_credit_balance;
  INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                    actor_type, actor_id, reference_id, note)
  VALUES (v_reseller.user_id, -v_req.diamonds_requested, 'reseller_credit', v_credit_balance, 'reseller_recharge',
          v_actor_type, p_actor, v_req.id,
          'credit sold to requester, approved by ' || COALESCE(v_admin_code, left(p_actor::TEXT, 8)));

  UPDATE public.recharge_requests SET status='approved', processed_by=p_actor, processed_at=NOW()
   WHERE id = p_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.approve_recharge_request(UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_recharge_request(UUID,UUID) TO service_role, authenticated;

-- ---------------------------------------------------------------------
-- 2. reject_recharge_request RPC — same scoping as approve. Previously
--    rejection was a direct table update only admins could perform; now
--    the owning reseller can reject their own queue from the dashboard.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reject_recharge_request(
  p_request_id UUID, p_actor UUID, p_reason TEXT
) RETURNS VOID AS $$
DECLARE
  v_req_status TEXT;
  v_req_reseller_id UUID;
  v_is_admin BOOLEAN;
  v_own_agent_id UUID;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_actor AND role = 'admin'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    SELECT id INTO v_own_agent_id
      FROM public.reseller_agents
     WHERE user_id = p_actor AND is_active
     LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Only admins or active resellers can reject recharge requests';
    END IF;
  END IF;

  SELECT status, reseller_id INTO v_req_status, v_req_reseller_id
    FROM public.recharge_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;
  IF v_req_status <> 'pending' THEN RAISE EXCEPTION 'Request already processed'; END IF;

  IF NOT v_is_admin THEN
    IF v_req_reseller_id IS NULL OR v_req_reseller_id <> v_own_agent_id THEN
      RAISE EXCEPTION 'You can only manage requests submitted to your own reseller code';
    END IF;
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'Rejection reason required';
  END IF;

  UPDATE public.recharge_requests
     SET status='rejected',
         processed_by=p_actor,
         processed_at=NOW(),
         rejection_reason=left(trim(p_reason), 500)
   WHERE id = p_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.reject_recharge_request(UUID,UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reject_recharge_request(UUID,UUID,TEXT) TO service_role, authenticated;
