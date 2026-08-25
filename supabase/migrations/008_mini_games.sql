-- =====================================================================
-- 008_mini_games.sql — Mini-Games economy
-- Three games (2048 / tic_tac_toe / memory_match) awarding COINS through
-- a server-side bounded RPC. The client-submitted score is NEVER trusted:
-- plausibility bounds, per-session caps and daily session limits all live
-- inside award_game_coins(), and every payout writes a wallet_ledger row
-- atomically with the balance update.
--
-- IDEMPOTENT (safe to run multiple times). Do NOT modify 001–007.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Extend wallet_ledger.reason CHECK to allow 'game_reward'.
--    The 007 constraint is inline (unnamed) — locate it dynamically so
--    re-runs are safe.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_conname TEXT;
  v_def TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.wallet_ledger'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) LIKE '%game_reward%'
  ) THEN
    SELECT conname, pg_get_constraintdef(oid) INTO v_conname, v_def
      FROM pg_constraint
     WHERE conrelid = 'public.wallet_ledger'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) LIKE '%gift_sent%'
     LIMIT 1;
    IF FOUND THEN
      EXECUTE format('ALTER TABLE public.wallet_ledger DROP CONSTRAINT %I', v_conname);
      v_def := '''reseller_recharge'',''admin_grant'',''admin_deduction'',''gift_sent'',''gift_received'',''shop_purchase'',''withdraw_request'',''withdraw_reversal'',''pk_reward'',''game_reward'',''other''';
      EXECUTE format(
        'ALTER TABLE public.wallet_ledger ADD CONSTRAINT %I CHECK (reason IN (%s))',
        v_conname, v_def);
    ELSE
      RAISE EXCEPTION 'wallet_ledger reason CHECK constraint not found';
    END IF;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 2. Game configuration — server-side knobs (tune without redeploy).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.game_config (
  game_key             TEXT PRIMARY KEY,
  display_name         TEXT NOT NULL,
  is_active            BOOLEAN NOT NULL DEFAULT TRUE,
  coins_per_100_pts    NUMERIC NOT NULL CHECK (coins_per_100_pts >= 0),
  max_coins_per_session INTEGER NOT NULL CHECK (max_coins_per_session >= 0),
  min_moves_to_score   INTEGER NOT NULL DEFAULT 1 CHECK (min_moves_to_score >= 0),
  score_cap_per_move   INTEGER NOT NULL CHECK (score_cap_per_move > 0),
  max_sessions_per_day INTEGER NOT NULL DEFAULT 10 CHECK (max_sessions_per_day > 0)
);

INSERT INTO public.game_config (game_key, display_name, coins_per_100_pts,
                                max_coins_per_session, min_moves_to_score,
                                score_cap_per_move, max_sessions_per_day)
SELECT * FROM (VALUES
  ('2048',          '2048 Puzzle',   2.0::NUMERIC, 200,  1, 4000, 15),
  ('tic_tac_toe',   'Tic Tac Toe',  50.0::NUMERIC,  50,  5,  100, 20),
  ('memory_match',  'Memory Match',  5.0::NUMERIC,  60,  8,  125, 15)
) AS g(game_key, display_name, coins_per_100_pts, max_coins_per_session,
       min_moves_to_score, score_cap_per_move, max_sessions_per_day)
ON CONFLICT (game_key) DO NOTHING;

ALTER TABLE public.game_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "game_config_read_all" ON public.game_config;
CREATE POLICY "game_config_read_all" ON public.game_config FOR SELECT USING (TRUE);
-- Writes only via SQL editor / service role. No client INSERT policy.

-- ---------------------------------------------------------------------
-- 3. Session log — one row per submitted game (even 0-coin attempts),
--    so daily caps are enforceable and auditable.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.game_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  game_key TEXT NOT NULL REFERENCES public.game_config(game_key) ON DELETE CASCADE,
  score INTEGER NOT NULL CHECK (score >= 0),
  moves INTEGER NOT NULL CHECK (moves >= 0),
  coins_awarded INTEGER NOT NULL DEFAULT 0 CHECK (coins_awarded >= 0),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_game_sessions_user_day
  ON public.game_sessions(user_id, game_key, created_at DESC);

ALTER TABLE public.game_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "game_sessions_read_own" ON public.game_sessions;
CREATE POLICY "game_sessions_read_own" ON public.game_sessions FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
-- Inserts happen ONLY inside the SECURITY DEFINER RPC below.

-- ---------------------------------------------------------------------
-- 4. award_game_coins — THE only path that converts a score into coins.
--    Bounds enforced here make client-side score spoofing pointless:
--      a) implausible score-vs-moves  -> hard reject
--      b) per-session coin cap        -> capped payout
--      c) daily session limit         -> (n+1)th+ session earns exactly 0
--      d) every payout                -> wallet_ledger row, same txn
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.award_game_coins(
  p_user_id UUID, p_game_key TEXT, p_score INTEGER, p_moves INTEGER
) RETURNS JSONB AS $$
DECLARE
  v_cfg public.game_config;
  v_today_count INTEGER;
  v_awarded INTEGER := 0;
  v_capped BOOLEAN := FALSE;
  v_balance INTEGER;
  v_session_id UUID;
BEGIN
  -- -- basic input hygiene -------------------------------------------
  IF p_score IS NULL OR p_moves IS NULL THEN
    RAISE EXCEPTION 'score and moves are required';
  END IF;
  IF p_score < 0 OR p_moves < 0 THEN
    RAISE EXCEPTION 'score and moves must be non-negative';
  END IF;

  SELECT * INTO v_cfg FROM public.game_config WHERE game_key = p_game_key;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown game'; END IF;
  IF NOT v_cfg.is_active THEN RAISE EXCEPTION 'Game is disabled'; END IF;

  -- -- a) implausibility guard: score must fit the logged move count --
  IF p_score > 0 AND p_moves < v_cfg.min_moves_to_score THEN
    RAISE EXCEPTION 'Implausible score: % points claimed in % moves',
      p_score, p_moves;
  END IF;
  IF p_score > GREATEST(p_moves, 1)::BIGINT * v_cfg.score_cap_per_move THEN
    RAISE EXCEPTION 'Implausible score: % points exceeds achievable maximum for % moves',
      p_score, p_moves;
  END IF;

  -- -- b/c) daily session limit + per-session cap ---------------------
  SELECT COUNT(*)::INTEGER INTO v_today_count
    FROM public.game_sessions
   WHERE user_id = p_user_id
     AND game_key = p_game_key
     AND created_at >= date_trunc('day', NOW());

  IF v_today_count >= v_cfg.max_sessions_per_day THEN
    v_awarded := 0;
    v_capped := TRUE; -- over the daily limit: session logs, pays nothing
  ELSE
    v_awarded := LEAST(
      FLOOR(p_score * v_cfg.coins_per_100_pts / 100.0)::INTEGER,
      v_cfg.max_coins_per_session
    );
    IF v_awarded < 0 THEN v_awarded := 0; END IF;
  END IF;

  -- -- log the attempt FIRST so it counts against today's quota ------
  INSERT INTO public.game_sessions (user_id, game_key, score, moves, coins_awarded)
  VALUES (p_user_id, p_game_key, p_score, p_moves, v_awarded)
  RETURNING id INTO v_session_id;

  -- -- d) pay out + ledger, one transaction --------------------------
  IF v_awarded > 0 THEN
    UPDATE public.profiles SET coins = coins + v_awarded
     WHERE id = p_user_id
    RETURNING coins INTO v_balance;

    INSERT INTO public.wallet_ledger (user_id, amount, currency, balance_after, reason,
                                      actor_type, actor_id, reference_id, note)
    VALUES (p_user_id, v_awarded, 'coins', v_balance, 'game_reward',
            'user', p_user_id, v_session_id,
            v_cfg.game_key || ' score ' || p_score || ' in ' || p_moves || ' moves');
  ELSE
    SELECT coins INTO v_balance FROM public.profiles WHERE id = p_user_id;
  END IF;

  RETURN jsonb_build_object(
    'session_id', v_session_id,
    'coins_awarded', v_awarded,
    'balance_after', v_balance,
    'capped', v_capped,
    'sessions_used_today', v_today_count + 1,
    'max_sessions_per_day', v_cfg.max_sessions_per_day
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.award_game_coins(UUID,TEXT,INTEGER,INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.award_game_coins(UUID,TEXT,INTEGER,INTEGER)
  TO service_role, authenticated;
