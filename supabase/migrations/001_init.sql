-- ============================================
-- RAYZI CLONE - INITIAL DATABASE MIGRATION
-- Run in Supabase SQL Editor or via CLI
-- ============================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================
-- CORE TABLES
-- ============================================

-- Users (extends auth.users)
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  bio TEXT DEFAULT '',
  gender TEXT CHECK (gender IN ('male', 'female', 'other')),
  date_of_birth DATE,
  country TEXT DEFAULT '',
  language TEXT DEFAULT 'en',
  is_verified BOOLEAN DEFAULT FALSE,
  is_banned BOOLEAN DEFAULT FALSE,
  ban_reason TEXT,
  ban_until TIMESTAMP WITH TIME ZONE,
  coins INTEGER DEFAULT 0,
  diamonds INTEGER DEFAULT 0,
  level INTEGER DEFAULT 1,
  experience INTEGER DEFAULT 0,
  follower_count INTEGER DEFAULT 0,
  following_count INTEGER DEFAULT 0,
  total_streams INTEGER DEFAULT 0,
  total_stream_minutes INTEGER DEFAULT 0,
  agency_id UUID,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Agencies (for streamer management)
CREATE TABLE public.agencies (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  owner_id UUID REFERENCES public.profiles(id),
  description TEXT,
  logo_url TEXT,
  commission_rate DECIMAL(5,2) DEFAULT 10.00,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Agency Members
CREATE TABLE public.agency_members (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agency_id UUID REFERENCES public.agencies(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'streamer' CHECK (role IN ('owner', 'manager', 'streamer')),
  commission_rate DECIMAL(5,2) DEFAULT 50.00,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(agency_id, user_id)
);

-- Follows
CREATE TABLE public.follows (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  follower_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  following_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(follower_id, following_id)
);

-- Live Streams
CREATE TABLE public.streams (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  host_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  thumbnail_url TEXT,
  channel_name TEXT UNIQUE NOT NULL,
  agora_token TEXT,
  status TEXT DEFAULT 'upcoming' CHECK (status IN ('upcoming', 'live', 'ended', 'banned')),
  category TEXT DEFAULT 'general',
  is_private BOOLEAN DEFAULT FALSE,
  password TEXT,
  max_viewers INTEGER DEFAULT 0,
  current_viewers INTEGER DEFAULT 0,
  total_viewers INTEGER DEFAULT 0,
  likes_count INTEGER DEFAULT 0,
  started_at TIMESTAMP WITH TIME ZONE,
  ended_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Stream Viewers (for tracking who's watching)
CREATE TABLE public.stream_viewers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  stream_id UUID REFERENCES public.streams(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  left_at TIMESTAMP WITH TIME ZONE,
  UNIQUE(stream_id, user_id)
);

-- Gifts Catalog
CREATE TABLE public.gifts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  description TEXT,
  image_url TEXT NOT NULL,
  animation_url TEXT,
  price_coins INTEGER NOT NULL,
  diamond_value INTEGER NOT NULL,
  category TEXT DEFAULT 'standard',
  is_limited BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Gift Transactions
CREATE TABLE public.gift_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  receiver_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  stream_id UUID REFERENCES public.streams(id) ON DELETE SET NULL,
  gift_id UUID REFERENCES public.gifts(id),
  quantity INTEGER DEFAULT 1,
  total_coins INTEGER NOT NULL,
  total_diamonds INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Wallet Transactions
CREATE TABLE public.wallet_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('purchase', 'gift_sent', 'gift_received', 'withdrawal', 'bonus', 'refund')),
  amount INTEGER NOT NULL,
  currency TEXT NOT NULL CHECK (currency IN ('coins', 'diamonds')),
  description TEXT,
  reference_id UUID,
  status TEXT DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed', 'cancelled')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Coin Packages (for in-app purchases)
CREATE TABLE public.coin_packages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  coins INTEGER NOT NULL,
  price_usd DECIMAL(10,2) NOT NULL,
  bonus_coins INTEGER DEFAULT 0,
  is_popular BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Push Tokens
CREATE TABLE public.push_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT DEFAULT 'fcm' CHECK (platform IN ('fcm', 'apns', 'onesignal')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, token)
);

-- Posts (short videos / moments)
CREATE TABLE public.posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT,
  media_urls TEXT[] DEFAULT '{}',
  media_type TEXT DEFAULT 'image' CHECK (media_type IN ('image', 'video')),
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  shares_count INTEGER DEFAULT 0,
  is_pinned BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Post Likes
CREATE TABLE public.post_likes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(post_id, user_id)
);

-- Post Comments
CREATE TABLE public.post_comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  parent_id UUID REFERENCES public.post_comments(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  likes_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Chat Messages (persisted chat history)
CREATE TABLE public.chat_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  stream_id UUID REFERENCES public.streams(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  message_type TEXT DEFAULT 'text' CHECK (message_type IN ('text', 'gift', 'system', 'join', 'leave')),
  content TEXT NOT NULL,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Private Messages
CREATE TABLE public.private_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  receiver_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Notifications
CREATE TABLE public.notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('follow', 'like', 'comment', 'gift', 'stream_start', 'system', 'mention')),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB DEFAULT '{}',
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Reports
CREATE TABLE public.reports (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reporter_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  reported_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  stream_id UUID REFERENCES public.streams(id) ON DELETE SET NULL,
  post_id UUID REFERENCES public.posts(id) ON DELETE SET NULL,
  reason TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'reviewing', 'resolved', 'dismissed')),
  admin_notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  resolved_at TIMESTAMP WITH TIME ZONE
);

-- Rooms (group chat / audio rooms)
CREATE TABLE public.rooms (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  host_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  category TEXT DEFAULT 'general',
  max_participants INTEGER DEFAULT 8,
  is_private BOOLEAN DEFAULT FALSE,
  password TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'closed')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Room Participants
CREATE TABLE public.room_participants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'listener' CHECK (role IN ('host', 'speaker', 'listener')),
  is_muted BOOLEAN DEFAULT FALSE,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(room_id, user_id)
);

-- Games / PK Battles
CREATE TABLE public.pk_battles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  stream_id_1 UUID REFERENCES public.streams(id),
  stream_id_2 UUID REFERENCES public.streams(id),
  host_id_1 UUID REFERENCES public.profiles(id),
  host_id_2 UUID REFERENCES public.profiles(id),
  score_1 INTEGER DEFAULT 0,
  score_2 INTEGER DEFAULT 0,
  winner_id UUID REFERENCES public.profiles(id),
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'ended')),
  started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  ended_at TIMESTAMP WITH TIME ZONE
);

-- Leaderboards (daily/weekly/monthly)
CREATE TABLE public.leaderboards (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  period TEXT NOT NULL CHECK (period IN ('daily', 'weekly', 'monthly', 'all_time')),
  category TEXT NOT NULL CHECK (category IN ('streamer', 'gifter', 'earner')),
  score INTEGER DEFAULT 0,
  rank INTEGER,
  date DATE NOT NULL,
  UNIQUE(user_id, period, category, date)
);

-- ============================================
-- INDEXES
-- ============================================
CREATE INDEX idx_streams_status ON public.streams(status);
CREATE INDEX idx_streams_host ON public.streams(host_id);
CREATE INDEX idx_streams_started ON public.streams(started_at);
CREATE INDEX idx_follows_follower ON public.follows(follower_id);
CREATE INDEX idx_follows_following ON public.follows(following_id);
CREATE INDEX idx_gift_tx_sender ON public.gift_transactions(sender_id);
CREATE INDEX idx_gift_tx_receiver ON public.gift_transactions(receiver_id);
CREATE INDEX idx_gift_tx_stream ON public.gift_transactions(stream_id);
CREATE INDEX idx_wallet_tx_user ON public.wallet_transactions(user_id);
CREATE INDEX idx_posts_user ON public.posts(user_id);
CREATE INDEX idx_chat_stream ON public.chat_messages(stream_id);
CREATE INDEX idx_private_msg_sender ON private_messages(sender_id);
CREATE INDEX idx_private_msg_receiver ON private_messages(receiver_id);
CREATE INDEX idx_notifications_user ON public.notifications(user_id);
CREATE INDEX idx_reports_status ON public.reports(status);
CREATE INDEX idx_leaderboards_period ON public.leaderboards(period, category, date);
CREATE INDEX idx_push_tokens_user ON public.push_tokens(user_id);

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.streams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.private_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gift_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_participants ENABLE ROW LEVEL SECURITY;

-- Profiles: users can read all, update own
CREATE POLICY "Profiles read all" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Profiles update own" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Streams: read all live, create own, update own
CREATE POLICY "Streams read" ON public.streams FOR SELECT USING (true);
CREATE POLICY "Streams create own" ON public.streams FOR INSERT WITH CHECK (auth.uid() = host_id);
CREATE POLICY "Streams update own" ON public.streams FOR UPDATE USING (auth.uid() = host_id);

-- Posts: read all, create own, update own, delete own
CREATE POLICY "Posts read" ON public.posts FOR SELECT USING (true);
CREATE POLICY "Posts create own" ON public.posts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Posts update own" ON public.posts FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Posts delete own" ON public.posts FOR DELETE USING (auth.uid() = user_id);

-- Post likes: read all, insert/delete own
CREATE POLICY "Post likes read" ON public.post_likes FOR SELECT USING (true);
CREATE POLICY "Post likes insert" ON public.post_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Post likes delete" ON public.post_likes FOR DELETE USING (auth.uid() = user_id);

-- Post comments: read all, insert own
CREATE POLICY "Comments read" ON public.post_comments FOR SELECT USING (true);
CREATE POLICY "Comments insert" ON public.post_comments FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Chat messages: read if participated, insert any authenticated
CREATE POLICY "Chat read" ON public.chat_messages FOR SELECT USING (true);
CREATE POLICY "Chat insert" ON public.chat_messages FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Private messages: read if sender/receiver
CREATE POLICY "PM read own" ON public.private_messages FOR SELECT USING (auth.uid() = sender_id OR auth.uid() = receiver_id);
CREATE POLICY "PM insert" ON public.private_messages FOR INSERT WITH CHECK (auth.uid() = sender_id);

-- Notifications: read own
CREATE POLICY "Notif read own" ON public.notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Notif insert" ON public.notifications FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Notif update own" ON public.notifications FOR UPDATE USING (auth.uid() = user_id);

-- Wallet: read own
CREATE POLICY "Wallet read own" ON public.wallet_transactions FOR SELECT USING (auth.uid() = user_id);

-- Gifts: read all
CREATE POLICY "Gifts read" ON public.gifts FOR SELECT USING (true);

-- Push tokens: manage own
CREATE POLICY "Push tokens own" ON public.push_tokens FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Rooms: read all, create own, update own
CREATE POLICY "Rooms read" ON public.rooms FOR SELECT USING (true);
CREATE POLICY "Rooms insert own" ON public.rooms FOR INSERT WITH CHECK (auth.uid() = host_id);
CREATE POLICY "Rooms update own" ON public.rooms FOR UPDATE USING (auth.uid() = host_id);

-- Room participants: read all, manage own
CREATE POLICY "Room participants read" ON public.room_participants FOR SELECT USING (true);
CREATE POLICY "Room participants insert" ON public.room_participants FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Room participants delete" ON public.room_participants FOR DELETE USING (auth.uid() = user_id);

-- ============================================
-- FUNCTIONS & TRIGGERS
-- ============================================

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER posts_updated_at BEFORE UPDATE ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER post_comments_updated_at BEFORE UPDATE ON public.post_comments
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- Update follower counts
CREATE OR REPLACE FUNCTION public.update_follower_counts()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.profiles SET follower_count = follower_count + 1 WHERE id = NEW.following_id;
    UPDATE public.profiles SET following_count = following_count + 1 WHERE id = NEW.follower_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.profiles SET follower_count = follower_count - 1 WHERE id = OLD.following_id;
    UPDATE public.profiles SET following_count = following_count - 1 WHERE id = OLD.follower_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER follow_counts AFTER INSERT OR DELETE ON public.follows
  FOR EACH ROW EXECUTE FUNCTION public.update_follower_counts();

-- Update post likes count
CREATE OR REPLACE FUNCTION public.update_post_likes()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.posts SET likes_count = likes_count - 1 WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER post_likes_count AFTER INSERT OR DELETE ON public.post_likes
  FOR EACH ROW EXECUTE FUNCTION public.update_post_likes();

-- Update post comments count
CREATE OR REPLACE FUNCTION public.update_post_comments()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.posts SET comments_count = comments_count - 1 WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER post_comments_count AFTER INSERT OR DELETE ON public.post_comments
  FOR EACH ROW EXECUTE FUNCTION public.update_post_comments();

-- Update stream viewer count
CREATE OR REPLACE FUNCTION public.update_stream_viewers()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.streams SET current_viewers = current_viewers + 1, total_viewers = total_viewers + 1 WHERE id = NEW.stream_id;
  ELSIF TG_OP = 'UPDATE' AND NEW.left_at IS NOT NULL AND OLD.left_at IS NULL THEN
    UPDATE public.streams SET current_viewers = GREATEST(current_viewers - 1, 0) WHERE id = NEW.stream_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER stream_viewers_count AFTER INSERT OR UPDATE ON public.stream_viewers
  FOR EACH ROW EXECUTE FUNCTION public.update_stream_viewers();

-- Create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, username, display_name, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'username', 'user_' || substr(NEW.id::text, 1, 8)),
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'display_name', 'User'),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', 'https://api.dicebear.com/7.x/avataaars/svg?seed=' || NEW.id)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Increment total_streams when host goes live
CREATE OR REPLACE FUNCTION public.increment_total_streams()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'live' AND OLD.status <> 'live' THEN
    UPDATE public.profiles SET total_streams = total_streams + 1 WHERE id = NEW.host_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER streams_total_count AFTER UPDATE OF status ON public.streams
  FOR EACH ROW EXECUTE FUNCTION public.increment_total_streams();

-- ============================================
-- SEED DATA
-- ============================================
INSERT INTO public.gifts (name, description, image_url, price_coins, diamond_value, category, sort_order) VALUES
('Rose', 'A beautiful red rose', 'https://cdn.example.com/gifts/rose.png', 10, 1, 'standard', 1),
('Heart', 'Show your love', 'https://cdn.example.com/gifts/heart.png', 50, 5, 'standard', 2),
('Teddy Bear', 'Cute teddy bear', 'https://cdn.example.com/gifts/teddy.png', 100, 10, 'standard', 3),
('Crown', 'Royal crown', 'https://cdn.example.com/gifts/crown.png', 500, 50, 'premium', 4),
('Super Car', 'Luxury sports car', 'https://cdn.example.com/gifts/car.png', 1000, 100, 'premium', 5),
('Yacht', 'Private yacht', 'https://cdn.example.com/gifts/yacht.png', 5000, 500, 'luxury', 6),
('Castle', 'Dream castle', 'https://cdn.example.com/gifts/castle.png', 10000, 1000, 'luxury', 7);

INSERT INTO public.coin_packages (name, coins, price_usd, bonus_coins, is_popular, sort_order) VALUES
('Starter Pack', 100, 0.99, 0, FALSE, 1),
('Basic Pack', 550, 4.99, 50, TRUE, 2),
('Standard Pack', 1200, 9.99, 200, FALSE, 3),
('Premium Pack', 6500, 49.99, 1500, TRUE, 4),
('Ultimate Pack', 14000, 99.99, 4000, FALSE, 5);