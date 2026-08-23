-- =====================================================================
-- 005_feature_expansion.sql — PHM Live v2 feature expansion
-- Spec: phm_live_feature_expansion_spec.md
-- Additive + IDEMPOTENT (safe to run multiple times).
-- Do NOT modify or re-run 001/002/003.
-- Adaptations vs spec §3 (repo reality):
--   * posts/post_likes/post_comments already exist (001) — only ALTER.
--   * pk_battles already exists (001, stream_id_1/2 naming) — only ALTER.
--   * migration number is 005 (004 = seed_example_reels).
-- =====================================================================

-- ---------------------------------------------------------------------
-- A1. NEWSFEED: extend existing posts table (spec §3 newsfeed)
-- ---------------------------------------------------------------------
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS visibility TEXT DEFAULT 'public';
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS is_removed BOOLEAN DEFAULT FALSE;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'posts_visibility_check') THEN
    ALTER TABLE public.posts ADD CONSTRAINT posts_visibility_check
      CHECK (visibility IN ('public','followers'));
  END IF;
END $$;

-- Stories -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.stories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  author_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  media_url TEXT NOT NULL,
  media_type TEXT DEFAULT 'image' CHECK (media_type IN ('image','video')),
  expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '24 hours'),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.story_views (
  story_id UUID REFERENCES public.stories(id) ON DELETE CASCADE,
  viewer_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  viewed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (story_id, viewer_id)
);

-- Friends (mutual; distinct from one-way follows) ----------------------------
CREATE TABLE IF NOT EXISTS public.friend_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  requester_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  addressee_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(requester_id, addressee_id)
);
CREATE INDEX IF NOT EXISTS idx_friend_requests_addressee ON public.friend_requests(addressee_id, status);

-- ---------------------------------------------------------------------
-- A2/B. SHOP: badges / frames / VIP tiers / themes / entry animations /
--        name effects + inventory + equipped pointers
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shop_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  category TEXT NOT NULL CHECK (category IN ('badge','avatar_frame','vip_tier','theme','entry_animation','name_effect')),
  tier TEXT CHECK (tier IN ('king','crown','vvip','vip',NULL)),
  name TEXT NOT NULL,
  description TEXT,
  preview_url TEXT,
  price_diamonds INTEGER NOT NULL DEFAULT 0 CHECK (price_diamonds >= 0),
  duration_days INTEGER CHECK (duration_days IS NULL OR duration_days > 0),
  effect_config JSONB, -- for name_effect items: {"prefix_emojis":[..],"suffix_emojis":[..],"gradient_colors":[..]}
  is_active BOOLEAN DEFAULT TRUE,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_shop_items_category ON public.shop_items(category, is_active);

-- Stable identity for seeding/upserts keyed on (category, name).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'shop_items_category_name_key') THEN
    ALTER TABLE public.shop_items ADD CONSTRAINT shop_items_category_name_key UNIQUE (category, name);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.user_inventory (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  item_id UUID REFERENCES public.shop_items(id) ON DELETE CASCADE,
  is_equipped BOOLEAN DEFAULT FALSE,
  purchased_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE,
  UNIQUE(user_id, item_id)
);
CREATE INDEX IF NOT EXISTS idx_inventory_user ON public.user_inventory(user_id);

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS equipped_frame_id UUID REFERENCES public.shop_items(id);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS equipped_badge_id UUID REFERENCES public.shop_items(id);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS equipped_theme_id UUID REFERENCES public.shop_items(id);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS equipped_entry_animation_id UUID REFERENCES public.shop_items(id);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS name_effect JSONB DEFAULT NULL;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS camera_prefs JSONB DEFAULT '{"filter":"natural","beauty_level":0,"brightness":0}'::jsonb;

-- Atomic purchase RPC — price looked up server-side ONLY (audit C1/C3).
-- Takes explicit p_user_id: the API's service-role client has no auth.uid()
-- context; the caller id comes from the backend's authenticated request.
DROP FUNCTION IF EXISTS public.purchase_shop_item(UUID);
CREATE OR REPLACE FUNCTION public.purchase_shop_item(p_user_id UUID, p_item_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_item public.shop_items;
  v_inv public.user_inventory;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM public.shop_items WHERE id = p_item_id AND is_active = TRUE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;

  UPDATE public.profiles SET diamonds = diamonds - v_item.price_diamonds
   WHERE id = p_user_id AND diamonds >= v_item.price_diamonds;
  IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient diamonds'; END IF;

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
  -- refund on any failure after deduction
  IF v_item.id IS NOT NULL AND SQLSTATE <> 'P0001' THEN
    UPDATE public.profiles SET diamonds = diamonds + v_item.price_diamonds WHERE id = p_user_id;
  END IF;
  RAISE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.purchase_shop_item(UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.purchase_shop_item(UUID,UUID) TO authenticated;

-- Equip RPC — verifies ownership server-side, unequips previous same-category.
DROP FUNCTION IF EXISTS public.equip_inventory_item(UUID, BOOLEAN);
CREATE OR REPLACE FUNCTION public.equip_inventory_item(p_user_id UUID, p_inventory_id UUID, p_equip BOOLEAN)
RETURNS JSONB AS $$
DECLARE
  v_row RECORD;
  v_col TEXT;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT ui.*, si.category AS item_category INTO v_row
  FROM public.user_inventory ui JOIN public.shop_items si ON si.id = ui.item_id
  WHERE ui.id = p_inventory_id AND ui.user_id = p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inventory item not found'; END IF;

  v_col := CASE v_row.item_category
    WHEN 'avatar_frame' THEN 'equipped_frame_id'
    WHEN 'badge' THEN 'equipped_badge_id'
    WHEN 'theme' THEN 'equipped_theme_id'
    WHEN 'entry_animation' THEN 'equipped_entry_animation_id'
    ELSE NULL END;

  IF p_equip THEN
    IF v_col IS NOT NULL THEN
      EXECUTE format(
        'UPDATE public.user_inventory SET is_equipped = FALSE WHERE user_id = $1 AND is_equipped AND item_id IN (SELECT id FROM public.shop_items WHERE category = %L)',
        v_row.item_category) USING p_user_id;
      EXECUTE format('UPDATE public.profiles SET %I = $2 WHERE id = $1', v_col)
        USING p_user_id, v_row.item_id;
    END IF;
    IF v_row.item_category = 'name_effect' THEN
      UPDATE public.profiles SET name_effect = si.effect_config
      FROM public.shop_items si WHERE si.id = v_row.item_id AND public.profiles.id = p_user_id;
    END IF;
    UPDATE public.user_inventory SET is_equipped = TRUE WHERE id = p_inventory_id;
  ELSE
    IF v_col IS NOT NULL THEN
      EXECUTE format('UPDATE public.profiles SET %I = NULL WHERE id = $1', v_col) USING p_user_id;
    END IF;
    IF v_row.item_category = 'name_effect' THEN
      UPDATE public.profiles SET name_effect = NULL WHERE id = p_user_id;
    END IF;
    UPDATE public.user_inventory SET is_equipped = FALSE WHERE id = p_inventory_id;
  END IF;

  RETURN jsonb_build_object('inventory_id', p_inventory_id, 'equipped', p_equip);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.equip_inventory_item(UUID,UUID,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.equip_inventory_item(UUID,UUID,BOOLEAN) TO authenticated;

-- ---------------------------------------------------------------------
-- D. RESELLER RECHARGE SYSTEM
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.reseller_agents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE UNIQUE,
  diamond_credit_balance BIGINT DEFAULT 0 CHECK (diamond_credit_balance >= 0),
  commission_rate DECIMAL(5,2) DEFAULT 5.00,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.recharge_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  requester_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  reseller_id UUID REFERENCES public.reseller_agents(id),
  diamonds_requested INTEGER NOT NULL CHECK (diamonds_requested > 0),
  payment_proof_url TEXT,
  note TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  processed_by UUID REFERENCES public.profiles(id),
  processed_at TIMESTAMP WITH TIME ZONE,
  rejection_reason TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_recharge_status ON public.recharge_requests(status);

-- Admin approve → atomic debit reseller credit + credit requester diamonds.
CREATE OR REPLACE FUNCTION public.approve_recharge_request(p_request_id UUID, p_admin UUID)
RETURNS VOID AS $$
DECLARE
  v_req public.recharge_requests;
  v_reseller public.reseller_agents;
BEGIN
  SELECT * INTO v_req FROM public.recharge_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;
  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'Request already processed'; END IF;

  SELECT * INTO v_reseller FROM public.reseller_agents WHERE id = v_req.reseller_id FOR UPDATE;
  IF NOT FOUND OR NOT v_reseller.is_active THEN RAISE EXCEPTION 'Reseller not available'; END IF;
  IF v_reseller.diamond_credit_balance < v_req.diamonds_requested THEN
    RAISE EXCEPTION 'Reseller has insufficient diamond credit';
  END IF;

  UPDATE public.reseller_agents SET diamond_credit_balance = diamond_credit_balance - v_req.diamonds_requested
   WHERE id = v_reseller.id;
  UPDATE public.profiles SET diamonds = diamonds + v_req.diamonds_requested WHERE id = v_req.requester_id;
  UPDATE public.recharge_requests SET status='approved', processed_by=p_admin, processed_at=NOW()
   WHERE id = p_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.approve_recharge_request(UUID,UUID) FROM PUBLIC;

-- ---------------------------------------------------------------------
-- D2. HOST APPLICATION SYSTEM
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.host_applications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  phone_number TEXT NOT NULL,
  id_document_url TEXT,
  sample_video_url TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  reviewed_by UUID REFERENCES public.profiles(id),
  reviewed_at TIMESTAMP WITH TIME ZONE,
  rejection_reason TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_host_apps_status ON public.host_applications(status);

-- ---------------------------------------------------------------------
-- E/A3. LEADERBOARD RPC (gifters|hosts × period × rewardable)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_leaderboard(
  p_type TEXT,
  p_period TEXT,
  p_rewardable BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(user_id UUID, score BIGINT, rank INTEGER) AS $$
BEGIN
  IF p_period NOT IN ('daily','weekly','monthly','all') THEN
    RAISE EXCEPTION 'Invalid period';
  END IF;
  IF p_type = 'gifters' THEN
    RETURN QUERY
    SELECT gt.sender_id, SUM(gt.total_coins)::BIGINT AS score,
           RANK() OVER (ORDER BY SUM(gt.total_coins) DESC)::INTEGER AS rank
    FROM public.gift_transactions gt
    WHERE gt.sender_id IS NOT NULL
      AND (p_period = 'all'
        OR (p_period = 'daily' AND gt.created_at >= CURRENT_DATE)
        OR (p_period = 'weekly' AND gt.created_at >= CURRENT_DATE - INTERVAL '7 days')
        OR (p_period = 'monthly' AND gt.created_at >= CURRENT_DATE - INTERVAL '30 days'))
      AND (NOT p_rewardable OR gt.sender_id IN (SELECT id FROM public.profiles WHERE is_verified = TRUE))
    GROUP BY gt.sender_id
    ORDER BY score DESC
    LIMIT 100;
  ELSIF p_type = 'hosts' THEN
    RETURN QUERY
    SELECT gt.receiver_id, SUM(gt.total_coins)::BIGINT AS score,
           RANK() OVER (ORDER BY SUM(gt.total_coins) DESC)::INTEGER AS rank
    FROM public.gift_transactions gt
    WHERE gt.receiver_id IS NOT NULL
      AND (p_period = 'all'
        OR (p_period = 'daily' AND gt.created_at >= CURRENT_DATE)
        OR (p_period = 'weekly' AND gt.created_at >= CURRENT_DATE - INTERVAL '7 days')
        OR (p_period = 'monthly' AND gt.created_at >= CURRENT_DATE - INTERVAL '30 days'))
      AND (NOT p_rewardable OR gt.receiver_id IN (SELECT id FROM public.profiles WHERE is_verified = TRUE))
    GROUP BY gt.receiver_id
    ORDER BY score DESC
    LIMIT 100;
  ELSE
    RAISE EXCEPTION 'Invalid type';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.get_leaderboard(TEXT,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_leaderboard(TEXT,TEXT,BOOLEAN) TO authenticated;

-- ---------------------------------------------------------------------
-- F. RANDOM PK BATTLE + DUAL DRAGON (extends existing pk_battles from 001)
-- ---------------------------------------------------------------------
ALTER TABLE public.pk_battles ADD COLUMN IF NOT EXISTS duration_seconds INTEGER DEFAULT 300;
ALTER TABLE public.pk_battles ADD COLUMN IF NOT EXISTS dragon_stage_1 INTEGER DEFAULT 0;
ALTER TABLE public.pk_battles ADD COLUMN IF NOT EXISTS dragon_stage_2 INTEGER DEFAULT 0;
ALTER TABLE public.pk_battles DROP CONSTRAINT IF EXISTS pk_battles_status_check;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pk_battles_status_check') THEN
    ALTER TABLE public.pk_battles ADD CONSTRAINT pk_battles_status_check
      CHECK (status IN ('active','ended','forfeited'));
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pk_battles_dragon_1_check') THEN
    ALTER TABLE public.pk_battles ADD CONSTRAINT pk_battles_dragon_1_check
      CHECK (dragon_stage_1 BETWEEN 0 AND 4);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pk_battles_dragon_2_check') THEN
    ALTER TABLE public.pk_battles ADD CONSTRAINT pk_battles_dragon_2_check
      CHECK (dragon_stage_2 BETWEEN 0 AND 4);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.pk_matchmaking_queue (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  stream_id UUID REFERENCES public.streams(id) ON DELETE CASCADE UNIQUE,
  queued_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.pk_dragon_stages (
  stage INTEGER PRIMARY KEY,
  label TEXT NOT NULL,
  score_threshold INTEGER NOT NULL,
  animation_url TEXT
);
INSERT INTO public.pk_dragon_stages (stage, label, score_threshold)
SELECT * FROM (VALUES
  (0,'Egg',0),(1,'Hatchling',500),(2,'Juvenile',2000),(3,'Adult',5000),(4,'Legendary',10000)
) AS s(stage,label,score_threshold)
WHERE NOT EXISTS (SELECT 1 FROM public.pk_dragon_stages)
ON CONFLICT (stage) DO NOTHING;

-- Atomic PK scoring — called by backend gift service ONLY (single write path).
CREATE OR REPLACE FUNCTION public.pk_apply_score(p_stream_id UUID, p_amount INTEGER)
RETURNS JSONB AS $$
DECLARE
  v_battle public.pk_battles;
  v_side INTEGER;
  v_new_score INTEGER;
  v_thresholds INTEGER[];
  v_new_stage INTEGER := 0;
  v_stage INTEGER;
BEGIN
  IF p_amount <= 0 THEN RETURN NULL; END IF;
  SELECT * INTO v_battle FROM public.pk_battles
   WHERE status = 'active' AND (stream_id_1 = p_stream_id OR stream_id_2 = p_stream_id)
   ORDER BY started_at DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RETURN NULL; END IF;

  v_side := CASE WHEN v_battle.stream_id_1 = p_stream_id THEN 1 ELSE 2 END;
  IF v_side = 1 THEN
    v_new_score := v_battle.score_1 + p_amount;
    UPDATE public.pk_battles SET score_1 = v_new_score WHERE id = v_battle.id;
  ELSE
    v_new_score := v_battle.score_2 + p_amount;
    UPDATE public.pk_battles SET score_2 = v_new_score WHERE id = v_battle.id;
  END IF;

  SELECT array_agg(score_threshold ORDER BY stage) INTO v_thresholds FROM public.pk_dragon_stages;
  FOREACH v_stage IN ARRAY v_thresholds LOOP
    IF v_new_score >= v_stage THEN v_new_stage := v_new_stage + 1; END IF;
  END LOOP;
  v_new_stage := LEAST(v_new_stage - 1, 4);
  IF v_new_stage < 0 THEN v_new_stage := 0; END IF;

  IF v_side = 1 THEN
    UPDATE public.pk_battles SET dragon_stage_1 = v_new_stage WHERE id = v_battle.id;
  ELSE
    UPDATE public.pk_battles SET dragon_stage_2 = v_new_stage WHERE id = v_battle.id;
  END IF;

  RETURN jsonb_build_object('battle_id', v_battle.id, 'side', v_side, 'score', v_new_score,
                            'dragon_stage', v_new_stage);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.pk_apply_score(UUID,INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pk_apply_score(UUID,INTEGER) TO service_role, authenticated;

-- ---------------------------------------------------------------------
-- H. INBOX: conversations + messages (60s reel cap enforced by CHECK)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_a_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_b_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_message_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_a_id, user_b_id)
);

CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  message_type TEXT NOT NULL CHECK (message_type IN ('text','photo','video_reel','call_log')),
  text_content TEXT,
  media_url TEXT,
  media_duration_seconds INTEGER CHECK (
    message_type != 'video_reel' OR (media_duration_seconds IS NOT NULL AND media_duration_seconds <= 60)
  ),
  call_type TEXT CHECK (call_type IN ('audio','video',NULL)),
  call_duration_seconds INTEGER,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON public.messages(conversation_id, created_at);

-- ---------------------------------------------------------------------
-- RLS — every new table (mirrors 001/003 conventions)
-- ---------------------------------------------------------------------
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.story_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reseller_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recharge_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.host_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pk_matchmaking_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pk_dragon_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Posts read all" ON public.posts;
CREATE POLICY "Posts read all" ON public.posts FOR SELECT USING (NOT is_removed OR is_removed IS NULL);
DROP POLICY IF EXISTS "Posts update own" ON public.posts;
CREATE POLICY "Posts update own" ON public.posts FOR UPDATE USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Posts delete own" ON public.posts;
CREATE POLICY "Posts delete own" ON public.posts FOR DELETE USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "stories_read_all" ON public.stories;
CREATE POLICY "stories_read_all" ON public.stories FOR SELECT USING (expires_at > NOW());
DROP POLICY IF EXISTS "stories_insert_own" ON public.stories;
CREATE POLICY "stories_insert_own" ON public.stories FOR INSERT WITH CHECK (auth.uid() = author_id);
DROP POLICY IF EXISTS "stories_delete_own" ON public.stories;
CREATE POLICY "stories_delete_own" ON public.stories FOR DELETE USING (auth.uid() = author_id);

DROP POLICY IF EXISTS "story_views_insert_own" ON public.story_views;
CREATE POLICY "story_views_insert_own" ON public.story_views FOR INSERT WITH CHECK (auth.uid() = viewer_id);
DROP POLICY IF EXISTS "story_views_read_author_or_self" ON public.story_views;
CREATE POLICY "story_views_read_author_or_self" ON public.story_views FOR SELECT
  USING (auth.uid() = viewer_id OR auth.uid() IN (SELECT author_id FROM public.stories s WHERE s.id = story_id));

DROP POLICY IF EXISTS "friend_requests_read_parties" ON public.friend_requests;
CREATE POLICY "friend_requests_read_parties" ON public.friend_requests FOR SELECT
  USING (auth.uid() IN (requester_id, addressee_id));
DROP POLICY IF EXISTS "friend_requests_insert_own" ON public.friend_requests;
CREATE POLICY "friend_requests_insert_own" ON public.friend_requests FOR INSERT WITH CHECK (auth.uid() = requester_id);
DROP POLICY IF EXISTS "friend_requests_update_parties" ON public.friend_requests;
CREATE POLICY "friend_requests_update_parties" ON public.friend_requests FOR UPDATE
  USING (auth.uid() IN (requester_id, addressee_id));

DROP POLICY IF EXISTS "shop_items_read_all" ON public.shop_items;
CREATE POLICY "shop_items_read_all" ON public.shop_items FOR SELECT USING (is_active = TRUE OR public.is_admin());

DROP POLICY IF EXISTS "inventory_read_own" ON public.user_inventory;
CREATE POLICY "inventory_read_own" ON public.user_inventory FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "reseller_read_own_or_admin" ON public.reseller_agents;
CREATE POLICY "reseller_read_own_or_admin" ON public.reseller_agents FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "recharge_read_own_or_admin" ON public.recharge_requests;
CREATE POLICY "recharge_read_own_or_admin" ON public.recharge_requests FOR SELECT
  USING (auth.uid() = requester_id OR public.is_admin());
DROP POLICY IF EXISTS "recharge_insert_own" ON public.recharge_requests;
CREATE POLICY "recharge_insert_own" ON public.recharge_requests FOR INSERT WITH CHECK (auth.uid() = requester_id);

DROP POLICY IF EXISTS "host_app_read_own_or_admin" ON public.host_applications;
CREATE POLICY "host_app_read_own_or_admin" ON public.host_applications FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "host_app_insert_own" ON public.host_applications;
CREATE POLICY "host_app_insert_own" ON public.host_applications FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "pk_queue_insert_host" ON public.pk_matchmaking_queue;
CREATE POLICY "pk_queue_insert_host" ON public.pk_matchmaking_queue FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.streams s WHERE s.id = stream_id AND s.host_id = auth.uid()));
DROP POLICY IF EXISTS "pk_queue_delete_host" ON public.pk_matchmaking_queue;
CREATE POLICY "pk_queue_delete_host" ON public.pk_matchmaking_queue FOR DELETE
  USING (EXISTS (SELECT 1 FROM public.streams s WHERE s.id = stream_id AND s.host_id = auth.uid()));
DROP POLICY IF EXISTS "pk_queue_read_all" ON public.pk_matchmaking_queue;
CREATE POLICY "pk_queue_read_all" ON public.pk_matchmaking_queue FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS "pk_dragon_stages_read_all" ON public.pk_dragon_stages;
CREATE POLICY "pk_dragon_stages_read_all" ON public.pk_dragon_stages FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS "conversations_own" ON public.conversations;
CREATE POLICY "conversations_own" ON public.conversations FOR SELECT
  USING (auth.uid() IN (user_a_id, user_b_id));
DROP POLICY IF EXISTS "messages_own_conversation" ON public.messages;
CREATE POLICY "messages_own_conversation" ON public.messages FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.conversations c WHERE c.id = conversation_id AND auth.uid() IN (c.user_a_id, c.user_b_id)));
DROP POLICY IF EXISTS "messages_insert_own" ON public.messages;
CREATE POLICY "messages_insert_own" ON public.messages FOR INSERT WITH CHECK (auth.uid() = sender_id);
