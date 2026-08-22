-- ============================================
-- RAYZI CLONE - SQL FUNCTIONS (Appendix 11.1)
-- ============================================

-- Wallet functions
CREATE OR REPLACE FUNCTION public.deduct_coins(p_user_id UUID, p_amount INTEGER)
RETURNS VOID AS $$
BEGIN
  UPDATE public.profiles 
  SET coins = coins - p_amount 
  WHERE id = p_user_id AND coins >= p_amount;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Insufficient coins';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.add_coins(p_user_id UUID, p_amount INTEGER)
RETURNS VOID AS $$
BEGIN
  UPDATE public.profiles SET coins = coins + p_amount WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.add_diamonds(p_user_id UUID, p_amount INTEGER)
RETURNS VOID AS $$
BEGIN
  UPDATE public.profiles SET diamonds = diamonds + p_amount WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.deduct_diamonds(p_user_id UUID, p_amount INTEGER)
RETURNS VOID AS $$
BEGIN
  UPDATE public.profiles 
  SET diamonds = diamonds - p_amount 
  WHERE id = p_user_id AND diamonds >= p_amount;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Insufficient diamonds';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Stream likes
CREATE OR REPLACE FUNCTION public.increment_stream_likes(stream_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE public.streams SET likes_count = likes_count + 1 WHERE id = stream_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Post comments count
CREATE OR REPLACE FUNCTION public.increment_post_comments(post_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE public.posts SET comments_count = comments_count + 1 WHERE id = post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Admin dashboard stats
CREATE OR REPLACE FUNCTION public.get_admin_dashboard_stats()
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'total_users', (SELECT COUNT(*) FROM public.profiles),
    'live_streams', (SELECT COUNT(*) FROM public.streams WHERE status = 'live'),
    'total_gifts', (SELECT COALESCE(SUM(quantity), 0) FROM public.gift_transactions),
    'pending_reports', (SELECT COUNT(*) FROM public.reports WHERE status = 'pending'),
    'pending_withdrawals', (SELECT COUNT(*) FROM public.wallet_transactions WHERE type = 'withdrawal' AND status = 'pending'),
    'total_revenue', (SELECT COALESCE(SUM(amount), 0) FROM public.wallet_transactions WHERE type = 'purchase' AND status = 'completed'),
    'new_users_today', (SELECT COUNT(*) FROM public.profiles WHERE created_at >= CURRENT_DATE),
    'active_streams_today', (SELECT COUNT(*) FROM public.streams WHERE started_at >= CURRENT_DATE)
  ) INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Top streamers leaderboard
CREATE OR REPLACE FUNCTION public.get_top_streamers(period TEXT)
RETURNS TABLE(user_id UUID, score INTEGER) AS $$
BEGIN
  RETURN QUERY
  SELECT s.host_id, COALESCE(SUM(EXTRACT(EPOCH FROM (s.ended_at - s.started_at))/60)::INTEGER, 0) as score
  FROM public.streams s
  WHERE s.status = 'ended'
    AND CASE 
      WHEN period = 'daily' THEN s.started_at >= CURRENT_DATE
      WHEN period = 'weekly' THEN s.started_at >= CURRENT_DATE - INTERVAL '7 days'
      WHEN period = 'monthly' THEN s.started_at >= CURRENT_DATE - INTERVAL '30 days'
      ELSE TRUE
    END
  GROUP BY s.host_id
  ORDER BY score DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Top gifters leaderboard
CREATE OR REPLACE FUNCTION public.get_top_gifters(period TEXT)
RETURNS TABLE(user_id UUID, score INTEGER) AS $$
BEGIN
  RETURN QUERY
  SELECT gt.sender_id, COALESCE(SUM(gt.total_coins), 0)::INTEGER as score
  FROM public.gift_transactions gt
  WHERE CASE 
    WHEN period = 'daily' THEN gt.created_at >= CURRENT_DATE
    WHEN period = 'weekly' THEN gt.created_at >= CURRENT_DATE - INTERVAL '7 days'
    WHEN period = 'monthly' THEN gt.created_at >= CURRENT_DATE - INTERVAL '30 days'
    ELSE TRUE
  END
  GROUP BY gt.sender_id
  ORDER BY score DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Set admin role (run once for your admin user):
-- UPDATE auth.users SET raw_user_meta_data = raw_user_meta_data || '{"role":"admin"}' WHERE email = 'your-admin@email.com';