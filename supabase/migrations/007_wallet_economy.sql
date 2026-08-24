-- =====================================================================
-- 007_wallet_economy.sql — Advanced Coin Economy
-- Reseller/Admin shareable codes · wallet_ledger (single source of
-- truth) · withdraw requests with hold/reversal · admin adjustments.
--
-- IDEMPOTENT (safe to run multiple times). Do NOT modify 001–006.
-- Every balance change below happens inside ONE plpgsql statement =
-- one transaction, with row locks (FOR UPDATE) where two accounts move.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Economy configuration (server-side knobs, tunable without deploy)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.economy_config (
  key TEXT PRIMARY KEY,
  value NUMERIC NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
INSERT INTO public.economy_config (key, value)
SELECT * FROM (VALUES
  ('withdraw_min_diamonds',        500::NUMERIC),
  ('withdraw_daily_cap_diamonds',  50000::NUMERIC),
  ('diamond_to_payout_rate',       0.5::NUMERIC)   -- 1 diamond = 0.50 BDT-equivalent
) AS c(key,value)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.economy_config_value(p_key TEXT)
RETURNS NUMERIC AS $$
DECLARE v NUMERIC;
BEGIN
  SELECT value INTO v FROM public.economy_config WHERE key = p_key;
  RETURN COALESCE(v, 0);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.economy_config_value(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.economy_config_value(TEXT) TO service_role;

-- ---------------------------------------------------------------------
-- 1. Human-readable Reseller & Admin IDs
-- ---------------------------------------------------------------------
ALTER TABLE public.reseller_agents ADD COLUMN IF NOT EXISTS reseller_code TEXT;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reseller_agents_reseller_code_key') THEN
    ALTER TABLE public.reseller_agents ADD CONSTRAINT reseller_agents_reseller_code_key UNIQUE (reseller_code);
  END IF;
END $$;

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS admin_code TEXT;
-- Only admins carry an admin_code (partial unique index).
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_admin_code
  ON public.profiles(admin_code) WHERE admin_code IS NOT NULL;

-- Dynamic-safe generator (no regclass tricks): checks a fully-qualified query.
CREATE OR REPLACE FUNCTION public.next_shareable_code(p_prefix TEXT, p_digits INT, p_kind TEXT)
RETURNS TEXT AS $$
DECLARE
  v_code TEXT;
  v_max BIGINT := power(10, p_digits)::BIGINT - 1;
  v_min BIGINT := power(10, p_digits - 1)::BIGINT;
  v_tries INT := 0;
BEGIN
  LOOP
    v_code := p_prefix || floor(random() * (v_max - v_min + 1) + v_min)::BIGINT::TEXT;
    v_tries := v_tries + 1;
    IF v_tries > 100 THEN
      RAISE EXCEPTION 'Could not generate a unique code — namespace exhausted';
    END IF;
    IF p_kind = 'reseller' AND NOT EXISTS (
      SELECT 1 FROM public.reseller_agents WHERE reseller_code = v_code) THEN
      EXIT;
    END IF;
    IF p_kind = 'admin' AND NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE admin_code = v_code) THEN
      EXIT;
    END IF;
  END LOOP;
  RETURN v_code;
END;
$$ LANGUAGE plpgsql VOLATILE;
REVOKE ALL ON FUNCTION public.next_shareable_code(TEXT,INT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.next_shareable_code(TEXT,INT,TEXT) TO service_role;

-- Auto-assign reseller_code on insert when absent.
DROP TRIGGER IF EXISTS trg_reseller_code ON public.reseller_agents;
CREATE OR REPLACE FUNCTION public.assign_reseller_code()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.reseller_code IS NULL OR NEW.reseller_code = '' THEN
    NEW.reseller_code := public.next_shareable_code('RID-', 4, 'reseller');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_reseller_code
  BEFORE INSERT ON public.reseller_agents
  FOR EACH ROW EXECUTE FUNCTION public.assign_reseller_code();

-- Auto-assign admin_code when a profile becomes admin.
DROP TRIGGER IF EXISTS trg_admin_code ON public.profiles;
CREATE OR REPLACE FUNCTION public.assign_admin_code()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.role = 'admin' AND (NEW.admin_code IS NULL OR NEW.admin_code = '') THEN
    NEW.admin_code := public.next_shareable_code('ADM-', 3, 'admin');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_admin_code
  BEFORE INSERT OR UPDATE OF role ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.assign_admin_code();

-- Backfill existing rows (idempotent).
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT id FROM public.reseller_agents WHERE reseller_code IS NULL LOOP
    UPDATE public.reseller_agents SET reseller_code = public.next_shareable_code('RID-',4,'reseller')
    WHERE id = r.id;
  END LOOP;
  FOR r IN SELECT id FROM public.profiles WHERE role = 'admin' AND admin_code IS NULL LOOP
    UPDATE public.profiles SET admin_code = public.next_shareable_code('ADM-',3,'admin')
    WHERE id = r.id;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 2. WALLET LEDGER — single source of truth for every coin movement.
--    Deviation from spec (documented): +currency column, because the app
--    carries TWO spendable currencies (coins for gifts, diamonds for
--    shop/withdrawals) and an audit trail that cannot tell them apart
--    would fail its own purpose.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallet_ledger (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount BIGINT NOT NULL, -- positive = credit, negative = debit
  currency TEXT NOT NULL DEFAULT 'coins' CHECK (currency IN ('coins','diamonds','reseller_credit')),
  balance_after BIGINT NOT NULL,
  reason TEXT NOT NULL CHECK (reason IN (
    'reseller_recharge','admin_grant','admin_deduction','gift_sent',
    'gift_received','shop_purchase','withdraw_request','withdraw_reversal',
    'pk_reward','other'
  )),
  actor_type TEXT NOT NULL CHECK (actor_type IN ('user','reseller','admin','system')),
  actor_id UUID REFERENCES public.profiles(id),
  reference_id UUID, -- polymorphic FK (recharge/withdraw/purchase/gift ids)
  note TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_wallet_ledger_user_time ON public.wallet_ledger(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_ledger_actor ON public.wallet_ledger(actor_type, actor_id);

ALTER TABLE public.wallet_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ledger_read_own_or_admin" ON public.wallet_ledger;
CREATE POLICY "ledger_read_own_or_admin" ON public.wallet_ledger FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
-- Writes happen ONLY inside SECURITY DEFINER RPCs (same transaction as the
-- balance update). No direct INSERT policy on purpose.

-- ---------------------------------------------------------------------
-- 3. WITHDRAW REQUESTS — hold-on-submit / reverse-on-reject flow
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.withdraw_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  diamonds_requested INTEGER NOT NULL CHECK (diamonds_requested > 0),
  payout_amount NUMERIC(12,2), -- computed server-side from economy_config rate
  payout_method TEXT NOT NULL CHECK (payout_method IN ('bkash','nagad','bank_transfer','other')),
  payout_details JSONB NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','paid')),
  processed_by UUID REFERENCES public.profiles(id),
  processed_at TIMESTAMP WITH TIME ZONE,
  rejection_reason TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_withdraw_status ON public.withdraw_requests(status);
CREATE INDEX IF NOT EXISTS idx_withdraw_user ON public.withdraw_requests(user_id, created_at DESC);

ALTER TABLE public.withdraw_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "withdraw_read_own_or_admin" ON public.withdraw_requests;
CREATE POLICY "withdraw_read_own_or_admin" ON public.withdraw_requests FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "withdraw_insert_own" ON public.withdraw_requests;
CREATE POLICY "withdraw_insert_own" ON public.withdraw_requests FOR INSERT
  WITH CHECK (auth.uid() = user_id);
-- status transitions run through SECURITY DEFINER RPCs only.

-- ---------------------------------------------------------------------
-- 4. RETROFIT core wallet RPCs — every mutation now writes the ledger
--    in the SAME statement/transaction as the balance update.
--    New params are optional (defaults) → existing callers keep working,
--    but the old 2-arg overloads are dropped so nothing can bypass it.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.deduct_coins(UUID, INTEGER);
CREATE OR REPLACE FUNCTION public.deduct_coins(
  p_user_id UUID, p_amount INTEGER,
  p_reason TEXT DEFAULT 'gift_sent', p_actor_type TEXT DEFAULT 'user',
  p_actor_id UUID DEFAULT NULL, p_reference_id UUID DEFAULT NULL, p_note TEXT DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE v_balance INTEGER;
BEGIN
  UPDATE public.profiles SET coins = coins - p_amount
   WHERE id = p_user_id AND coins >= p_amount
  RETURNING coins INTO v_balance;
  IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient coins'; END IF;

  INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                    actor_type, actor_id, reference_id, note)
  VALUES (p_user_id, -p_amount, 'coins', v_balance, p_reason,
          p_actor_type, COALESCE(p_actor_id, p_user_id), p_reference_id, p_note);
  RETURN v_balance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.deduct_coins(UUID,INTEGER,TEXT,TEXT,UUID,UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.deduct_coins(UUID,INTEGER,TEXT,TEXT,UUID,UUID,TEXT) TO service_role;

DROP FUNCTION IF EXISTS public.add_coins(UUID, INTEGER);
CREATE OR REPLACE FUNCTION public.add_coins(
  p_user_id UUID, p_amount INTEGER,
  p_reason TEXT DEFAULT 'other', p_actor_type TEXT DEFAULT 'system',
  p_actor_id UUID DEFAULT NULL, p_reference_id UUID DEFAULT NULL, p_note TEXT DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE v_balance INTEGER;
BEGIN
  UPDATE public.profiles SET coins = coins + p_amount
   WHERE id = p_user_id
  RETURNING coins INTO v_balance;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

  INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                    actor_type, actor_id, reference_id, note)
  VALUES (p_user_id, p_amount, 'coins', v_balance, p_reason,
          p_actor_type, COALESCE(p_actor_id, p_user_id), p_reference_id, p_note);
  RETURN v_balance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.add_coins(UUID,INTEGER,TEXT,TEXT,UUID,UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_coins(UUID,INTEGER,TEXT,TEXT,UUID,UUID,TEXT) TO service_role;

DROP FUNCTION IF EXISTS public.add_diamonds(UUID, INTEGER);
CREATE OR REPLACE FUNCTION public.add_diamonds(
  p_user_id UUID, p_amount INTEGER,
  p_reason TEXT DEFAULT 'reseller_recharge', p_actor_type TEXT DEFAULT 'reseller',
  p_actor_id UUID DEFAULT NULL, p_reference_id UUID DEFAULT NULL, p_note TEXT DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE v_balance INTEGER;
BEGIN
  UPDATE public.profiles SET diamonds = diamonds + p_amount
   WHERE id = p_user_id
  RETURNING diamonds INTO v_balance;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

  INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                    actor_type, actor_id, reference_id, note)
  VALUES (p_user_id, p_amount, 'diamonds', v_balance, p_reason,
          p_actor_type, p_actor_id, p_reference_id, p_note);
  RETURN v_balance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.add_diamonds(UUID,INTEGER,TEXT,TEXT,UUID,UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_diamonds(UUID,INTEGER,TEXT,TEXT,UUID,UUID,TEXT) TO service_role;

DROP FUNCTION IF EXISTS public.deduct_diamonds(UUID, INTEGER);
CREATE OR REPLACE FUNCTION public.deduct_diamonds(
  p_user_id UUID, p_amount INTEGER,
  p_reason TEXT DEFAULT 'shop_purchase', p_actor_type TEXT DEFAULT 'user',
  p_actor_id UUID DEFAULT NULL, p_reference_id UUID DEFAULT NULL, p_note TEXT DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE v_balance INTEGER;
BEGIN
  UPDATE public.profiles SET diamonds = diamonds - p_amount
   WHERE id = p_user_id AND diamonds >= p_amount
  RETURNING diamonds INTO v_balance;
  IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient diamonds'; END IF;

  INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                    actor_type, actor_id, reference_id, note)
  VALUES (p_user_id, -p_amount, 'diamonds', v_balance, p_reason,
          p_actor_type, COALESCE(p_actor_id, p_user_id), p_reference_id, p_note);
  RETURN v_balance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.deduct_diamonds(UUID,INTEGER,TEXT,TEXT,UUID,UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.deduct_diamonds(UUID,INTEGER,TEXT,TEXT,UUID,UUID,TEXT) TO service_role;

-- ---------------------------------------------------------------------
-- 5. purchase_shop_item — now ledger-aware (same fix pattern)
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.purchase_shop_item(UUID, UUID);
CREATE OR REPLACE FUNCTION public.purchase_shop_item(p_user_id UUID, p_item_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_item public.shop_items;
  v_inv public.user_inventory;
  v_balance INTEGER;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM public.shop_items WHERE id = p_item_id AND is_active = TRUE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;

  UPDATE public.profiles SET diamonds = diamonds - v_item.price_diamonds
   WHERE id = p_user_id AND diamonds >= v_item.price_diamonds
  RETURNING diamonds INTO v_balance;
  IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient diamonds'; END IF;

  INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                    actor_type, actor_id, reference_id, note)
  VALUES (p_user_id, -v_item.price_diamonds, 'diamonds', v_balance, 'shop_purchase',
          'user', p_user_id, p_item_id, v_item.name);

  INSERT INTO public.user_inventory (user_id, item_id, expires_at)
  VALUES (p_user_id, p_item_id,
          CASE WHEN v_item.duration_days IS NULL THEN NULL ELSE NOW() + make_interval(days => v_item.duration_days) END)
  ON CONFLICT (user_id, item_id) DO UPDATE
    SET expires_at = CASE WHEN v_item.duration_days IS NULL THEN NULL
                          ELSE COALESCE(public.user_inventory.expires_at, NOW()) + make_interval(days => v_item.duration_days) END
  RETURNING * INTO v_inv;

  RETURN jsonb_build_object('inventory_id', v_inv.id, 'expires_at', v_inv.expires_at,
                            'diamonds_spent', v_item.price_diamonds);
EXCEPTION WHEN OTHERS THEN
  -- compensating refund on any failure after deduction (mirrors pre-ledger behaviour)
  IF v_item.id IS NOT NULL AND SQLSTATE <> 'P0001' THEN
    UPDATE public.profiles SET diamonds = diamonds + v_item.price_diamonds WHERE id = p_user_id;
    INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                      actor_type, actor_id, reference_id, note)
    SELECT p_user_id, v_item.price_diamonds, 'diamonds', diamonds, 'other',
           'system', p_user_id, p_item_id, 'refund: failed purchase'
    FROM public.profiles WHERE id = p_user_id;
  END IF;
  RAISE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.purchase_shop_item(UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.purchase_shop_item(UUID,UUID) TO authenticated;

-- ---------------------------------------------------------------------
-- 6. approve_recharge_request v2 — adds BOTH ledger sides atomically.
--    This build implements ADMIN-side approval (reseller approval UI not
--    built yet); the reseller stays the funding source recorded in notes.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.approve_recharge_request(UUID, UUID);
CREATE OR REPLACE FUNCTION public.approve_recharge_request(p_request_id UUID, p_admin UUID)
RETURNS VOID AS $$
DECLARE
  v_req public.recharge_requests;
  v_reseller public.reseller_agents;
  v_user_balance INTEGER;
  v_credit_balance BIGINT;
  v_admin_code TEXT;
BEGIN
  -- Defense-in-depth: the caller must be an admin profile.
  SELECT admin_code INTO v_admin_code FROM public.profiles WHERE id = p_admin AND role = 'admin';
  IF NOT FOUND THEN RAISE EXCEPTION 'Only admins can approve recharge requests'; END IF;

  SELECT * INTO v_req FROM public.recharge_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;
  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'Request already processed'; END IF;

  SELECT * INTO v_reseller FROM public.reseller_agents WHERE id = v_req.reseller_id FOR UPDATE;
  IF NOT FOUND OR NOT v_reseller.is_active THEN RAISE EXCEPTION 'Reseller not available'; END IF;
  IF v_reseller.diamond_credit_balance < v_req.diamonds_requested THEN
    RAISE EXCEPTION 'Reseller has insufficient diamond credit';
  END IF;

  -- Side 1: credit the requester.
  UPDATE public.profiles SET diamonds = diamonds + v_req.diamonds_requested
   WHERE id = v_req.requester_id
  RETURNING diamonds INTO v_user_balance;
  INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                    actor_type, actor_id, reference_id, note)
  VALUES (v_req.requester_id, v_req.diamonds_requested, 'diamonds', v_user_balance, 'reseller_recharge',
          'admin', p_admin, v_req.id,
          'via reseller ' || v_reseller.reseller_code || ', approved by ' || COALESCE(v_admin_code,'ADM'));

  -- Side 2: debit the reseller's credit stock.
  UPDATE public.reseller_agents SET diamond_credit_balance = diamond_credit_balance - v_req.diamonds_requested
   WHERE id = v_reseller.id
  RETURNING diamond_credit_balance INTO v_credit_balance;
  INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                    actor_type, actor_id, reference_id, note)
  VALUES (v_reseller.user_id, -v_req.diamonds_requested, 'reseller_credit', v_credit_balance, 'reseller_recharge',
          'admin', p_admin, v_req.id,
          'credit sold to requester, approved by ' || COALESCE(v_admin_code,'ADM'));

  UPDATE public.recharge_requests SET status='approved', processed_by=p_admin, processed_at=NOW()
   WHERE id = p_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.approve_recharge_request(UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_recharge_request(UUID,UUID) TO service_role;

-- ---------------------------------------------------------------------
-- 7. WITHDRAW flow RPCs
-- ---------------------------------------------------------------------
-- Submit: validates min/cap server-side, debits (holds) immediately,
-- computes payout server-side, writes ledger row. One transaction.
CREATE OR REPLACE FUNCTION public.create_withdraw_request(
  p_user_id UUID, p_diamonds INTEGER, p_method TEXT, p_details JSONB
) RETURNS JSONB AS $$
DECLARE
  v_balance INTEGER;
  v_min NUMERIC;
  v_cap NUMERIC;
  v_today BIGINT;
  v_rate NUMERIC;
  v_payout NUMERIC(12,2);
  v_request_id UUID;
BEGIN
  IF p_diamonds IS NULL OR p_diamonds <= 0 THEN
    RAISE EXCEPTION 'Invalid withdrawal amount';
  END IF;
  IF p_method NOT IN ('bkash','nagad','bank_transfer','other') THEN
    RAISE EXCEPTION 'Unsupported payout method';
  END IF;
  IF p_details IS NULL OR p_details = '{}'::jsonb THEN
    RAISE EXCEPTION 'Payout details required';
  END IF;

  v_min := public.economy_config_value('withdraw_min_diamonds');
  v_cap := public.economy_config_value('withdraw_daily_cap_diamonds');
  v_rate := public.economy_config_value('diamond_to_payout_rate');

  IF p_diamonds < v_min THEN
    RAISE EXCEPTION 'Minimum withdrawal is % diamonds', v_min;
  END IF;

  SELECT COALESCE(SUM(diamonds_requested),0) INTO v_today
  FROM public.withdraw_requests
  WHERE user_id = p_user_id AND status IN ('pending','approved','paid')
    AND created_at >= CURRENT_DATE;
  IF v_today + p_diamonds > v_cap THEN
    RAISE EXCEPTION 'Daily withdrawal cap exceeded (% diamonds)', v_cap;
  END IF;

  -- Hold the diamonds NOW so they cannot be double-spent while pending.
  UPDATE public.profiles SET diamonds = diamonds - p_diamonds
   WHERE id = p_user_id AND diamonds >= p_diamonds
  RETURNING diamonds INTO v_balance;
  IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient diamonds'; END IF;

  v_payout := ROUND(p_diamonds * v_rate, 2);

  INSERT INTO public.withdraw_requests (user_id, diamonds_requested, payout_amount,
                                        payout_method, payout_details, status)
  VALUES (p_user_id, p_diamonds, v_payout, p_method, p_details, 'pending')
  RETURNING id INTO v_request_id;

  INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                    actor_type, actor_id, reference_id, note)
  VALUES (p_user_id, -p_diamonds, 'diamonds', v_balance, 'withdraw_request',
          'user', p_user_id, v_request_id,
          format('%s withdrawal, payout %s (held)', p_method, v_payout));

  RETURN jsonb_build_object('id', v_request_id, 'payout_amount', v_payout,
                            'balance_after', v_balance);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.create_withdraw_request(UUID,INTEGER,TEXT,JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_withdraw_request(UUID,INTEGER,TEXT,JSONB) TO service_role;

-- Reject: reverses the hold, credits diamonds back, writes reversal row.
CREATE OR REPLACE FUNCTION public.admin_reject_withdraw(p_request_id UUID, p_admin UUID, p_reason TEXT)
RETURNS VOID AS $$
DECLARE
  v_req public.withdraw_requests;
  v_balance INTEGER;
  v_admin_code TEXT;
BEGIN
  SELECT admin_code INTO v_admin_code FROM public.profiles WHERE id = p_admin AND role = 'admin';
  IF NOT FOUND THEN RAISE EXCEPTION 'Only admins can process withdrawals'; END IF;

  SELECT * INTO v_req FROM public.withdraw_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;
  IF v_req.status NOT IN ('pending','approved') THEN
    RAISE EXCEPTION 'Request already processed';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'Rejection reason required';
  END IF;

  UPDATE public.profiles SET diamonds = diamonds + v_req.diamonds_requested
   WHERE id = v_req.user_id
  RETURNING diamonds INTO v_balance;

  INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                    actor_type, actor_id, reference_id, note)
  VALUES (v_req.user_id, v_req.diamonds_requested, 'diamonds', v_balance, 'withdraw_reversal',
          'admin', p_admin, v_req.id, 'rejected by ' || COALESCE(v_admin_code,'ADM') || ': ' || left(trim(p_reason), 300));

  UPDATE public.withdraw_requests SET status='rejected', processed_by=p_admin,
         processed_at=NOW(), rejection_reason=left(trim(p_reason),500)
  WHERE id = p_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.admin_reject_withdraw(UUID,UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reject_withdraw(UUID,UUID,TEXT) TO service_role;

-- Mark paid AFTER the real-world payout has been sent manually. No balance
-- change here — the hold at submit time already moved the diamonds out.
CREATE OR REPLACE FUNCTION public.admin_mark_withdraw_paid(p_request_id UUID, p_admin UUID)
RETURNS VOID AS $$
DECLARE
  v_status TEXT;
  v_admin_code TEXT;
BEGIN
  SELECT admin_code INTO v_admin_code FROM public.profiles WHERE id = p_admin AND role = 'admin';
  IF NOT FOUND THEN RAISE EXCEPTION 'Only admins can process withdrawals'; END IF;

  SELECT status INTO v_status FROM public.withdraw_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;
  IF v_status NOT IN ('pending','approved') THEN
    RAISE EXCEPTION 'Request already processed';
  END IF;

  UPDATE public.withdraw_requests SET status='paid', processed_by=p_admin, processed_at=NOW()
  WHERE id = p_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.admin_mark_withdraw_paid(UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mark_withdraw_paid(UUID,UUID) TO service_role;

-- Optional explicit approve step (pending → approved) for two-stage queues.
CREATE OR REPLACE FUNCTION public.admin_approve_withdraw(p_request_id UUID, p_admin UUID)
RETURNS VOID AS $$
DECLARE v_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_admin AND role = 'admin') THEN
    RAISE EXCEPTION 'Only admins can process withdrawals';
  END IF;
  SELECT status INTO v_status FROM public.withdraw_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;
  IF v_status <> 'pending' THEN RAISE EXCEPTION 'Request already processed'; END IF;
  UPDATE public.withdraw_requests SET status='approved', processed_by=p_admin, processed_at=NOW()
  WHERE id = p_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.admin_approve_withdraw(UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_approve_withdraw(UUID,UUID) TO service_role;

-- ---------------------------------------------------------------------
-- 8. ADMIN DIRECT COIN CONTROL
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_adjust_balance(
  p_admin UUID, p_user_id UUID, p_currency TEXT, p_amount BIGINT, p_note TEXT
) RETURNS JSONB AS $$
DECLARE
  v_admin_code TEXT;
  v_target_username TEXT;
  v_balance BIGINT;
  v_delta INTEGER;
BEGIN
  SELECT admin_code INTO v_admin_code FROM public.profiles WHERE id = p_admin AND role = 'admin';
  IF NOT FOUND THEN RAISE EXCEPTION 'Only admins can adjust balances'; END IF;
  IF p_note IS NULL OR length(trim(p_note)) < 3 THEN
    RAISE EXCEPTION 'A reason/note is required for every adjustment';
  END IF;
  IF p_currency NOT IN ('coins','diamonds') THEN
    RAISE EXCEPTION 'currency must be coins or diamonds';
  END IF;
  IF p_amount IS NULL OR p_amount = 0 THEN
    RAISE EXCEPTION 'amount must be non-zero';
  END IF;
  IF abs(p_amount) > 1000000000 THEN
    RAISE EXCEPTION 'amount exceeds sane operational bounds';
  END IF;

  SELECT username INTO v_target_username FROM public.profiles WHERE id = p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Target user not found'; END IF;

  v_delta := p_amount::INTEGER;
  IF p_currency = 'coins' THEN
    UPDATE public.profiles SET coins = coins + v_delta
     WHERE id = p_user_id AND coins + v_delta >= 0
    RETURNING coins INTO v_balance;
  ELSE
    UPDATE public.profiles SET diamonds = diamonds + v_delta
     WHERE id = p_user_id AND diamonds + v_delta >= 0
    RETURNING diamonds INTO v_balance;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Adjustment would make balance negative'; END IF;

  INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                    actor_type, actor_id, reference_id, note)
  VALUES (p_user_id, p_amount, p_currency, v_balance,
          CASE WHEN p_amount > 0 THEN 'admin_grant' ELSE 'admin_deduction' END,
          'admin', p_admin, p_user_id,
          'by ' || COALESCE(v_admin_code,'ADM') || ': ' || left(trim(p_note), 400));

  RETURN jsonb_build_object('user_id', p_user_id, 'username', v_target_username,
                            'currency', p_currency, 'amount', p_amount,
                            'balance_after', v_balance, 'admin_code', v_admin_code);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.admin_adjust_balance(UUID,UUID,TEXT,BIGINT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_adjust_balance(UUID,UUID,TEXT,BIGINT,TEXT) TO service_role;

-- Public reseller directory for the Buy-Coins screen (code + name only —
-- never raw agent UUIDs or credit balances).
CREATE OR REPLACE FUNCTION public.list_active_resellers()
RETURNS TABLE(reseller_code TEXT, display_name TEXT, username TEXT, commission_rate DECIMAL) AS $$
BEGIN
  RETURN QUERY
  SELECT ra.reseller_code, COALESCE(p.display_name, p.username), p.username, ra.commission_rate
  FROM public.reseller_agents ra
  JOIN public.profiles p ON p.id = ra.user_id
  WHERE ra.is_active = TRUE
  ORDER BY ra.created_at ASC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.list_active_resellers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_active_resellers() TO authenticated, service_role;
