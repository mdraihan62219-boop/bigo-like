# Rayzi Clone — Full CLI-Executable Specification
> **Project:** Smarty/Rayzi Live Streaming App Clone  
> **Stack:** Supabase (Free Tier) + Node.js + Flutter + Agora + Socket.IO  
> **Target:** CLI Agent (Claude CLI, OpenCode, Cursor Agent, etc.)  
> **License:** MIT (for generated code)

---

## Table of Contents
1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites & Accounts](#2-prerequisites--accounts)
3. [Supabase Setup](#3-supabase-setup)
4. [Node.js Backend](#4-nodejs-backend)
5. [Flutter Mobile App](#5-flutter-mobile-app)
6. [Android Build Setup](#6-android-build-setup)
7. [Admin Panel (Flutter Web)](#7-admin-panel-flutter-web)
8. [Docker & Deployment](#8-docker--deployment)
9. [CI/CD Pipeline](#9-cicd-pipeline)
10. [Testing & QA](#10-testing--qa)
11. [Appendices](#11-appendices)

---

## 1. Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Flutter App   │────▶│  Node.js API    │────▶│   Supabase      │
│  (iOS/Android)  │◄────│  (Express/SIO)  │◄────│  (PostgreSQL)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │
        ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│  Agora SDK      │     │  Socket.IO      │
│ (Live Stream)   │     │ (Real-time Chat)│
└─────────────────┘     └─────────────────┘
```

**Services (Free Tier):**
| Service | Purpose | Free Tier Limits |
|---------|---------|------------------|
| Supabase | DB, Auth, Storage, Edge Functions | 500MB DB, 1GB storage, 2M Edge Function invocations/mo |
| Agora | Live streaming & voice | 10,000 mins/mo free |
| GitHub | Repo + Actions CI/CD | 2,000 Actions minutes/mo |
| Firebase/OneSignal | Push notifications | Free tier available |
| Cloudflare | CDN / Custom domain | Free tier |

---

## 2. Prerequisites & Accounts

### 2.1 Required Accounts
Create these accounts before starting:

```bash
# 1. Supabase — https://supabase.com
echo "Create project, note: Project URL, anon key, service_role key"

# 2. Agora — https://www.agora.io
echo "Create project, note: App ID, App Certificate"

# 3. GitHub — https://github.com
echo "Create repo: rayzi-clone"

# 4. OneSignal — https://onesignal.com  (optional, can use Firebase FCM)
echo "Create app, note: App ID, REST API key"

# 5. Cloudflare — https://dash.cloudflare.com  (optional)
echo "For custom domain + CDN"
```

### 2.2 Local Tools
```bash
# Verify installations
node --version    # >= 18
npm --version     # >= 9
flutter --version # >= 3.19
dart --version    # >= 3.3
git --version
docker --version  # optional
```

### 2.3 Environment Variables Template
Create `~/.rayzi-env` (never commit this):

```bash
# Supabase
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...

# Agora
AGORA_APP_ID=xxxxxxxx
AGORA_APP_CERTIFICATE=xxxxxxxx

# Node.js
JWT_SECRET=your-super-secret-jwt-key-min-32-chars
PORT=3000
NODE_ENV=development

# OneSignal (optional)
ONESIGNAL_APP_ID=xxxxxxxx
ONESIGNAL_REST_API_KEY=xxxxxxxx

# Firebase (for FCM push)
FIREBASE_PROJECT_ID=xxxxxxxx
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n..."
FIREBASE_CLIENT_EMAIL=firebase-adminsdk@...iam.gserviceaccount.com
```

---

## 3. Supabase Setup

### 3.1 Create Project
```bash
# Via dashboard or CLI
npm install -g supabase
supabase login
supabase projects create rayzi-clone --org-id YOUR_ORG --region us-east-1 --plan free
```

### 3.2 Database Migrations
Run these SQL commands in Supabase SQL Editor (or save as `supabase/migrations/001_init.sql`):

```sql
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

-- Chat messages: read if participated, insert any authenticated
CREATE POLICY "Chat read" ON public.chat_messages FOR SELECT USING (true);
CREATE POLICY "Chat insert" ON public.chat_messages FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Private messages: read if sender/receiver
CREATE POLICY "PM read own" ON public.private_messages FOR SELECT USING (auth.uid() = sender_id OR auth.uid() = receiver_id);
CREATE POLICY "PM insert" ON public.private_messages FOR INSERT WITH CHECK (auth.uid() = sender_id);

-- Notifications: read own
CREATE POLICY "Notif read own" ON public.notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Notif insert" ON public.notifications FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Wallet: read own
CREATE POLICY "Wallet read own" ON public.wallet_transactions FOR SELECT USING (auth.uid() = user_id);

-- Gifts: read all
CREATE POLICY "Gifts read" ON public.gifts FOR SELECT USING (true);

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

-- Update stream viewer count
CREATE OR REPLACE FUNCTION public.update_stream_viewers()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.streams SET current_viewers = current_viewers + 1, total_viewers = total_viewers + 1 WHERE id = NEW.stream_id;
  ELSIF TG_OP = 'UPDATE' AND NEW.left_at IS NOT NULL AND OLD.left_at IS NULL THEN
    UPDATE public.streams SET current_viewers = current_viewers - 1 WHERE id = NEW.stream_id;
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
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'User'),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', 'https://api.dicebear.com/7.x/avataaars/svg?seed=' || NEW.id)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

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

INSERT INTO public.agencies (name, owner_id, description, commission_rate) VALUES
('Global Stars', NULL, 'Top streaming agency worldwide', 15.00),
('Rising Talents', NULL, 'New talent development', 10.00);
```

### 3.3 Storage Buckets
In Supabase Dashboard → Storage, create:
- `avatars` — public, 2MB limit, image/*
- `stream-thumbnails` — public, 5MB limit, image/*
- `post-media` — public, 10MB limit, image/*, video/*
- `gift-animations` — public, 2MB limit, image/gif, image/webp
- `room-covers` — public, 2MB limit, image/*

### 3.4 Edge Functions (Optional)
```bash
supabase functions new agora-token
supabase functions new send-notification
```

Save as `supabase/functions/agora-token/index.ts`:
```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { RtcTokenBuilder, RtcRole } from 'https://esm.sh/agora-token@2.0.3'

serve(async (req) => {
  const { channel_name, uid, role } = await req.json()
  const appId = Deno.env.get('AGORA_APP_ID')!
  const appCertificate = Deno.env.get('AGORA_APP_CERTIFICATE')!

  const expirationTimeInSeconds = 3600
  const currentTimestamp = Math.floor(Date.now() / 1000)
  const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds

  const token = RtcTokenBuilder.buildTokenWithUid(
    appId, appCertificate, channel_name, uid,
    role === 'host' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER,
    privilegeExpiredTs
  )

  return new Response(JSON.stringify({ token, expires_at: privilegeExpiredTs }), {
    headers: { 'Content-Type': 'application/json' }
  })
})
```

Deploy:
```bash
supabase secrets set AGORA_APP_ID=your_app_id AGORA_APP_CERTIFICATE=your_cert
supabase functions deploy agora-token
```

---

## 4. Node.js Backend

### 4.1 Project Setup
```bash
mkdir rayzi-backend && cd rayzi-backend
npm init -y

# Install dependencies
npm install express cors helmet morgan compression dotenv bcryptjs jsonwebtoken \
  socket.io ioredis multer @supabase/supabase-js agora-token firebase-admin \
  onesignal-node express-rate-limit express-validator node-cron axios

# Install dev dependencies
npm install -D nodemon typescript @types/express @types/cors @types/bcryptjs \
  @types/jsonwebtoken @types/multer @types/node ts-node

# Init TypeScript
npx tsc --init
```

### 4.2 tsconfig.json
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### 4.3 package.json scripts
```json
{
  "scripts": {
    "dev": "nodemon src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js",
    "lint": "eslint src --ext .ts"
  }
}
```

### 4.4 Directory Structure
```
src/
├── config/
│   ├── database.ts
│   ├── redis.ts
│   └── firebase.ts
├── middleware/
│   ├── auth.ts
│   ├── errorHandler.ts
│   ├── rateLimiter.ts
│   └── validate.ts
├── controllers/
│   ├── auth.controller.ts
│   ├── user.controller.ts
│   ├── stream.controller.ts
│   ├── gift.controller.ts
│   ├── post.controller.ts
│   ├── wallet.controller.ts
│   ├── room.controller.ts
│   ├── notification.controller.ts
│   ├── report.controller.ts
│   └── admin.controller.ts
├── routes/
│   ├── index.ts
│   ├── auth.routes.ts
│   ├── user.routes.ts
│   ├── stream.routes.ts
│   ├── gift.routes.ts
│   ├── post.routes.ts
│   ├── wallet.routes.ts
│   ├── room.routes.ts
│   ├── notification.routes.ts
│   ├── report.routes.ts
│   └── admin.routes.ts
├── services/
│   ├── agora.service.ts
│   ├── notification.service.ts
│   ├── wallet.service.ts
│   └── leaderboard.service.ts
├── utils/
│   ├── logger.ts
│   ├── response.ts
│   └── constants.ts
├── types/
│   └── index.ts
└── index.ts
```

### 4.5 Core Files

**src/config/database.ts**
```typescript
import { createClient, SupabaseClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.SUPABASE_URL!
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY!

export const supabase: SupabaseClient = createClient(supabaseUrl, supabaseKey, {
  auth: { autoRefreshToken: false, persistSession: false }
})
```

**src/config/redis.ts**
```typescript
import Redis from 'ioredis'

export const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  password: process.env.REDIS_PASSWORD,
  retryStrategy: (times) => Math.min(times * 50, 2000)
})

redis.on('connect', () => console.log('Redis connected'))
redis.on('error', (err) => console.error('Redis error:', err))
```

**src/config/firebase.ts**
```typescript
import admin from 'firebase-admin'

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL
    })
  })
}

export const messaging = admin.messaging()
```

**src/types/index.ts**
```typescript
import { Request } from 'express'

export interface AuthenticatedRequest extends Request {
  user?: {
    id: string
    email: string
    role: string
  }
}

export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
  error?: string
  meta?: {
    page?: number
    limit?: number
    total?: number
  }
}
```

**src/utils/response.ts**
```typescript
import { Response } from 'express'
import { ApiResponse } from '../types'

export const success = <T>(res: Response, data: T, message?: string, meta?: any) => {
  const response: ApiResponse<T> = { success: true, data, message, meta }
  return res.status(200).json(response)
}

export const created = <T>(res: Response, data: T, message?: string) => {
  return res.status(201).json({ success: true, data, message })
}

export const error = (res: Response, status: number, message: string) => {
  return res.status(status).json({ success: false, error: message })
}
```

**src/utils/logger.ts**
```typescript
export const logger = {
  info: (msg: string, meta?: any) => console.log(`[INFO] ${new Date().toISOString()} ${msg}`, meta || ''),
  error: (msg: string, meta?: any) => console.error(`[ERROR] ${new Date().toISOString()} ${msg}`, meta || ''),
  warn: (msg: string, meta?: any) => console.warn(`[WARN] ${new Date().toISOString()} ${msg}`, meta || '')
}
```

**src/middleware/auth.ts**
```typescript
import { Response, NextFunction } from 'express'
import jwt from 'jsonwebtoken'
import { AuthenticatedRequest } from '../types'
import { supabase } from '../config/database'

export const authenticate = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const token = req.headers.authorization?.split(' ')[1]
    if (!token) return res.status(401).json({ success: false, error: 'No token provided' })

    const decoded = jwt.verify(token, process.env.JWT_SECRET!) as any
    const { data: user } = await supabase.auth.getUser(token)
    if (!user.user) return res.status(401).json({ success: false, error: 'Invalid token' })

    req.user = { id: user.user.id, email: user.user.email!, role: user.user.role || 'user' }
    next()
  } catch (err) {
    return res.status(401).json({ success: false, error: 'Authentication failed' })
  }
}

export const requireAdmin = (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  if (req.user?.role !== 'admin') {
    return res.status(403).json({ success: false, error: 'Admin access required' })
  }
  next()
}
```

**src/middleware/errorHandler.ts**
```typescript
import { Request, Response, NextFunction } from 'express'
import { logger } from '../utils/logger'

export const errorHandler = (err: any, req: Request, res: Response, next: NextFunction) => {
  logger.error(err.message, { stack: err.stack, path: req.path })
  res.status(err.status || 500).json({
    success: false,
    error: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message
  })
}
```

**src/middleware/rateLimiter.ts**
```typescript
import rateLimit from 'express-rate-limit'

export const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: { success: false, error: 'Too many requests, please try again later' }
})

export const authLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 10,
  message: { success: false, error: 'Too many auth attempts, please try again later' }
})
```

### 4.6 Services

**src/services/agora.service.ts**
```typescript
import { RtcTokenBuilder, RtcRole } from 'agora-token'

const appId = process.env.AGORA_APP_ID!
const appCertificate = process.env.AGORA_APP_CERTIFICATE!

export class AgoraService {
  static generateToken(channelName: string, uid: number, role: 'host' | 'audience', expireHours = 24) {
    const expirationTimeInSeconds = expireHours * 3600
    const currentTimestamp = Math.floor(Date.now() / 1000)
    const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds
    const rtcRole = role === 'host' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER

    return RtcTokenBuilder.buildTokenWithUid(
      appId, appCertificate, channelName, uid, rtcRole, privilegeExpiredTs
    )
  }

  static generateChannelName(userId: string): string {
    return `stream_${userId}_${Date.now()}`
  }
}
```

**src/services/notification.service.ts**
```typescript
import { supabase } from '../config/database'
import { messaging } from '../config/firebase'
import { logger } from '../utils/logger'

export class NotificationService {
  static async create(userId: string, type: string, title: string, body: string, data: any = {}) {
    const { error } = await supabase.from('notifications').insert({
      user_id: userId, type, title, body, data
    })
    if (error) logger.error('Failed to create notification', error)
  }

  static async sendPush(userId: string, title: string, body: string, data: any = {}) {
    try {
      const { data: tokens } = await supabase
        .from('push_tokens')
        .select('token')
        .eq('user_id', userId)

      if (!tokens?.length) return

      const messages = tokens.map((t: any) => ({
        token: t.token,
        notification: { title, body },
        data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)]))
      }))

      await messaging.sendEach(messages)
    } catch (err) {
      logger.error('Push notification failed', err)
    }
  }

  static async broadcastToFollowers(userId: string, title: string, body: string, data: any = {}) {
    const { data: followers } = await supabase
      .from('follows')
      .select('follower_id')
      .eq('following_id', userId)

    if (!followers) return

    for (const f of followers) {
      await this.create(f.follower_id, 'stream_start', title, body, data)
    }
  }
}
```

**src/services/wallet.service.ts**
```typescript
import { supabase } from '../config/database'
import { logger } from '../utils/logger'

export class WalletService {
  static async deductCoins(userId: string, amount: number, description: string, referenceId?: string) {
    const { data: profile } = await supabase.from('profiles').select('coins').eq('id', userId).single()
    if (!profile || profile.coins < amount) throw new Error('Insufficient coins')

    const { error } = await supabase.rpc('deduct_coins', {
      p_user_id: userId, p_amount: amount
    })

    if (error) throw error

    await supabase.from('wallet_transactions').insert({
      user_id: userId, type: 'gift_sent', amount: -amount,
      currency: 'coins', description, reference_id: referenceId
    })
  }

  static async addDiamonds(userId: string, amount: number, description: string, referenceId?: string) {
    const { error } = await supabase.rpc('add_diamonds', {
      p_user_id: userId, p_amount: amount
    })

    if (error) throw error

    await supabase.from('wallet_transactions').insert({
      user_id: userId, type: 'gift_received', amount,
      currency: 'diamonds', description, reference_id: referenceId
    })
  }

  static async purchaseCoins(userId: string, packageId: string, amount: number) {
    await supabase.from('wallet_transactions').insert({
      user_id: userId, type: 'purchase', amount,
      currency: 'coins', description: `Purchased ${amount} coins`,
      status: 'pending'
    })
  }
}
```

**src/services/leaderboard.service.ts**
```typescript
import { supabase } from '../config/database'
import cron from 'node-cron'

export class LeaderboardService {
  static init() {
    cron.schedule('0 0 * * *', () => this.calculate('daily'))
    cron.schedule('0 0 * * 0', () => this.calculate('weekly'))
    cron.schedule('0 0 1 * *', () => this.calculate('monthly'))
  }

  static async calculate(period: 'daily' | 'weekly' | 'monthly') {
    const date = new Date().toISOString().split('T')[0]

    const { data: streamers } = await supabase.rpc('get_top_streamers', { period })
    if (streamers) {
      for (let i = 0; i < streamers.length; i++) {
        await supabase.from('leaderboards').upsert({
          user_id: streamers[i].user_id, period, category: 'streamer',
          score: streamers[i].score, rank: i + 1, date
        })
      }
    }

    const { data: gifters } = await supabase.rpc('get_top_gifters', { period })
    if (gifters) {
      for (let i = 0; i < gifters.length; i++) {
        await supabase.from('leaderboards').upsert({
          user_id: gifters[i].user_id, period, category: 'gifter',
          score: gifters[i].score, rank: i + 1, date
        })
      }
    }
  }
}
```

### 4.7 Controllers

**src/controllers/auth.controller.ts**
```typescript
import { Request, Response } from 'express'
import jwt from 'jsonwebtoken'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'

export class AuthController {
  static async register(req: Request, res: Response) {
    try {
      const { email, password, username, display_name } = req.body

      const { data: existing } = await supabase.from('profiles').select('id').eq('username', username).single()
      if (existing) return error(res, 400, 'Username already taken')

      const { data, error: authError } = await supabase.auth.signUp({
        email, password,
        options: { data: { username, display_name } }
      })

      if (authError) return error(res, 400, authError.message)

      const token = jwt.sign(
        { id: data.user!.id, email: data.user!.email },
        process.env.JWT_SECRET!, { expiresIn: '7d' }
      )

      return success(res, { user: data.user, token }, 'Registration successful')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async login(req: Request, res: Response) {
    try {
      const { email, password } = req.body
      const { data, error: authError } = await supabase.auth.signInWithPassword({ email, password })
      if (authError) return error(res, 401, authError.message)

      const token = jwt.sign(
        { id: data.user.id, email: data.user.email },
        process.env.JWT_SECRET!, { expiresIn: '7d' }
      )

      return success(res, { user: data.user, token }, 'Login successful')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async socialLogin(req: Request, res: Response) {
    try {
      const { provider, token } = req.body
      const { data, error: authError } = await supabase.auth.signInWithIdToken({ provider, token })
      if (authError) return error(res, 401, authError.message)

      const jwtToken = jwt.sign(
        { id: data.user.id, email: data.user.email },
        process.env.JWT_SECRET!, { expiresIn: '7d' }
      )

      return success(res, { user: data.user, token: jwtToken })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async me(req: any, res: Response) {
    try {
      const { data: profile } = await supabase.from('profiles').select('*').eq('id', req.user.id).single()
      return success(res, profile)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
```

**src/controllers/user.controller.ts**
```typescript
import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class UserController {
  static async getProfile(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { data: profile } = await supabase
        .from('profiles')
        .select('*, agencies(id, name)')
        .eq('id', id).single()

      if (!profile) return error(res, 404, 'User not found')
      return success(res, profile)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async updateProfile(req: AuthenticatedRequest, res: Response) {
    try {
      const updates = req.body
      const { data, error: updateError } = await supabase
        .from('profiles')
        .update(updates)
        .eq('id', req.user!.id)
        .select().single()

      if (updateError) return error(res, 400, updateError.message)
      return success(res, data, 'Profile updated')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async follow(req: AuthenticatedRequest, res: Response) {
    try {
      const { userId } = req.body
      if (userId === req.user!.id) return error(res, 400, 'Cannot follow yourself')

      const { error } = await supabase.from('follows').insert({
        follower_id: req.user!.id, following_id: userId
      })

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Followed successfully')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async unfollow(req: AuthenticatedRequest, res: Response) {
    try {
      const { userId } = req.body
      const { error } = await supabase.from('follows')
        .delete()
        .eq('follower_id', req.user!.id)
        .eq('following_id', userId)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Unfollowed successfully')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getFollowers(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { page = 1, limit = 20 } = req.query
      const { data, count } = await supabase
        .from('follows')
        .select('profiles!follows_follower_id_fkey(*)', { count: 'exact' })
        .eq('following_id', id)
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getFollowing(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { page = 1, limit = 20 } = req.query
      const { data, count } = await supabase
        .from('follows')
        .select('profiles!follows_following_id_fkey(*)', { count: 'exact' })
        .eq('follower_id', id)
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async search(req: AuthenticatedRequest, res: Response) {
    try {
      const { q } = req.query
      if (!q) return error(res, 400, 'Query required')

      const { data } = await supabase
        .from('profiles')
        .select('*')
        .or(`username.ilike.%${q}%,display_name.ilike.%${q}%`)
        .limit(20)

      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getLeaderboard(req: AuthenticatedRequest, res: Response) {
    try {
      const { period = 'daily', category = 'streamer' } = req.query
      const { data } = await supabase
        .from('leaderboards')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('period', period)
        .eq('category', category)
        .eq('date', new Date().toISOString().split('T')[0])
        .order('rank', { ascending: true })
        .limit(100)

      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
```

**src/controllers/stream.controller.ts**
```typescript
import { Response } from 'express'
import { supabase } from '../config/database'
import { AgoraService } from '../services/agora.service'
import { NotificationService } from '../services/notification.service'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class StreamController {
  static async create(req: AuthenticatedRequest, res: Response) {
    try {
      const { title, description, category, is_private, password } = req.body
      const channelName = AgoraService.generateChannelName(req.user!.id)
      const agoraToken = AgoraService.generateToken(
        channelName,
        parseInt(req.user!.id.replace(/-/g, '').slice(0, 8), 16),
        'host'
      )

      const { data, error: insertError } = await supabase.from('streams').insert({
        host_id: req.user!.id, title, description, category,
        channel_name: channelName, agora_token: agoraToken,
        is_private, password, status: 'live', started_at: new Date().toISOString()
      }).select().single()

      if (insertError) return error(res, 400, insertError.message)

      await NotificationService.broadcastToFollowers(
        req.user!.id, 'Stream Started',
        `${req.user!.email} is now live!`,
        { stream_id: data.id, channel_name: channelName }
      )

      return success(res, data, 'Stream created')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getToken(req: AuthenticatedRequest, res: Response) {
    try {
      const { streamId } = req.params
      const { data: stream } = await supabase.from('streams').select('*').eq('id', streamId).single()
      if (!stream) return error(res, 404, 'Stream not found')

      const isHost = stream.host_id === req.user!.id
      const uid = parseInt(req.user!.id.replace(/-/g, '').slice(0, 8), 16)
      const token = AgoraService.generateToken(stream.channel_name, uid, isHost ? 'host' : 'audience')

      return success(res, { token, channel_name: stream.channel_name, is_host: isHost })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      const { status = 'live', category, page = 1, limit = 20 } = req.query
      let query = supabase.from('streams').select('*, profiles!streams_host_id_fkey(*)', { count: 'exact' })

      if (status) query = query.eq('status', status)
      if (category) query = query.eq('category', category)

      const { data, count } = await query
        .order('started_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getById(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { data } = await supabase
        .from('streams')
        .select('*, profiles!streams_host_id_fkey(*), stream_viewers(user_id, joined_at)')
        .eq('id', id).single()

      if (!data) return error(res, 404, 'Stream not found')
      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async join(req: AuthenticatedRequest, res: Response) {
    try {
      const { streamId } = req.params
      const { error } = await supabase.from('stream_viewers').upsert({
        stream_id: streamId, user_id: req.user!.id, joined_at: new Date().toISOString()
      })

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Joined stream')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async leave(req: AuthenticatedRequest, res: Response) {
    try {
      const { streamId } = req.params
      const { error } = await supabase.from('stream_viewers')
        .update({ left_at: new Date().toISOString() })
        .eq('stream_id', streamId)
        .eq('user_id', req.user!.id)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Left stream')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async end(req: AuthenticatedRequest, res: Response) {
    try {
      const { streamId } = req.params
      const { data: stream } = await supabase.from('streams').select('host_id').eq('id', streamId).single()
      if (!stream || stream.host_id !== req.user!.id) return error(res, 403, 'Not authorized')

      const { error } = await supabase.from('streams')
        .update({ status: 'ended', ended_at: new Date().toISOString() })
        .eq('id', streamId)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Stream ended')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async like(req: AuthenticatedRequest, res: Response) {
    try {
      const { streamId } = req.params
      const { error } = await supabase.rpc('increment_stream_likes', { stream_id: streamId })
      if (error) return error(res, 400, error.message)
      return success(res, null, 'Liked')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
```

**src/controllers/gift.controller.ts**
```typescript
import { Response } from 'express'
import { supabase } from '../config/database'
import { WalletService } from '../services/wallet.service'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class GiftController {
  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      const { data } = await supabase.from('gifts').select('*').eq('is_active', true).order('sort_order')
      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async send(req: AuthenticatedRequest, res: Response) {
    try {
      const { stream_id, gift_id, receiver_id, quantity = 1 } = req.body

      const { data: gift } = await supabase.from('gifts').select('*').eq('id', gift_id).single()
      if (!gift) return error(res, 404, 'Gift not found')

      const totalCoins = gift.price_coins * quantity
      const totalDiamonds = gift.diamond_value * quantity

      await WalletService.deductCoins(req.user!.id, totalCoins, `Sent ${gift.name} x${quantity}`)
      await WalletService.addDiamonds(receiver_id, totalDiamonds, `Received ${gift.name} x${quantity}`)

      const { data: tx } = await supabase.from('gift_transactions').insert({
        sender_id: req.user!.id, receiver_id, stream_id, gift_id,
        quantity, total_coins: totalCoins, total_diamonds: totalDiamonds
      }).select().single()

      return success(res, tx, 'Gift sent successfully')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async getTransactions(req: AuthenticatedRequest, res: Response) {
    try {
      const { page = 1, limit = 20, type = 'sent' } = req.query
      const column = type === 'sent' ? 'sender_id' : 'receiver_id'

      const { data, count } = await supabase
        .from('gift_transactions')
        .select('*, gifts(*), profiles!gift_transactions_receiver_id_fkey(*)', { count: 'exact' })
        .eq(column, req.user!.id)
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
```

**src/controllers/post.controller.ts**
```typescript
import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class PostController {
  static async create(req: AuthenticatedRequest, res: Response) {
    try {
      const { content, media_urls, media_type } = req.body
      const { data, error: insertError } = await supabase.from('posts').insert({
        user_id: req.user!.id, content, media_urls, media_type
      }).select().single()

      if (insertError) return error(res, 400, insertError.message)
      return success(res, data, 'Post created')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      const { page = 1, limit = 20, user_id } = req.query
      let query = supabase.from('posts').select('*, profiles!posts_user_id_fkey(*)', { count: 'exact' })

      if (user_id) query = query.eq('user_id', user_id)

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getById(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { data } = await supabase
        .from('posts')
        .select('*, profiles!posts_user_id_fkey(*), post_comments(*, profiles!post_comments_user_id_fkey(*))')
        .eq('id', id).single()

      if (!data) return error(res, 404, 'Post not found')
      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async like(req: AuthenticatedRequest, res: Response) {
    try {
      const { postId } = req.params
      const { error } = await supabase.from('post_likes').insert({
        post_id: postId, user_id: req.user!.id
      })

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Liked')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async unlike(req: AuthenticatedRequest, res: Response) {
    try {
      const { postId } = req.params
      const { error } = await supabase.from('post_likes')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', req.user!.id)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Unliked')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async comment(req: AuthenticatedRequest, res: Response) {
    try {
      const { postId } = req.params
      const { content, parent_id } = req.body

      const { data, error: insertError } = await supabase.from('post_comments').insert({
        post_id: postId, user_id: req.user!.id, content, parent_id
      }).select().single()

      if (insertError) return error(res, 400, insertError.message)
      await supabase.rpc('increment_post_comments', { post_id: postId })

      return success(res, data, 'Comment added')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async delete(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { error } = await supabase.from('posts')
        .delete()
        .eq('id', id)
        .eq('user_id', req.user!.id)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Post deleted')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
```

**src/controllers/wallet.controller.ts**
```typescript
import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class WalletController {
  static async getBalance(req: AuthenticatedRequest, res: Response) {
    try {
      const { data: profile } = await supabase
        .from('profiles')
        .select('coins, diamonds')
        .eq('id', req.user!.id).single()

      return success(res, profile)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getTransactions(req: AuthenticatedRequest, res: Response) {
    try {
      const { page = 1, limit = 20, type, currency } = req.query
      let query = supabase.from('wallet_transactions').select('*', { count: 'exact' }).eq('user_id', req.user!.id)

      if (type) query = query.eq('type', type)
      if (currency) query = query.eq('currency', currency)

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async purchaseCoins(req: AuthenticatedRequest, res: Response) {
    try {
      const { amount } = req.body
      const { error } = await supabase.rpc('add_coins', {
        p_user_id: req.user!.id, p_amount: amount
      })

      if (error) return error(res, 400, error.message)

      await supabase.from('wallet_transactions').insert({
        user_id: req.user!.id, type: 'purchase', amount,
        currency: 'coins', description: `Purchased ${amount} coins`, status: 'completed'
      })

      return success(res, null, 'Coins purchased successfully')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async withdraw(req: AuthenticatedRequest, res: Response) {
    try {
      const { amount, method } = req.body
      const { data: profile } = await supabase.from('profiles').select('diamonds').eq('id', req.user!.id).single()

      if (!profile || profile.diamonds < amount) return error(res, 400, 'Insufficient diamonds')

      await supabase.rpc('deduct_diamonds', { p_user_id: req.user!.id, p_amount: amount })

      await supabase.from('wallet_transactions').insert({
        user_id: req.user!.id, type: 'withdrawal', amount: -amount,
        currency: 'diamonds', description: `Withdrawal via ${method}`, status: 'pending'
      })

      return success(res, null, 'Withdrawal request submitted')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
```

**src/controllers/room.controller.ts**
```typescript
import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class RoomController {
  static async create(req: AuthenticatedRequest, res: Response) {
    try {
      const { title, description, category, max_participants, is_private, password } = req.body
      const { data, error: insertError } = await supabase.from('rooms').insert({
        host_id: req.user!.id, title, description, category,
        max_participants, is_private, password
      }).select().single()

      if (insertError) return error(res, 400, insertError.message)
      return success(res, data, 'Room created')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      const { page = 1, limit = 20, category } = req.query
      let query = supabase.from('rooms').select('*, profiles!rooms_host_id_fkey(*)', { count: 'exact' }).eq('status', 'active')

      if (category) query = query.eq('category', category)

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async join(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId } = req.params
      const { password } = req.body

      const { data: room } = await supabase.from('rooms').select('*').eq('id', roomId).single()
      if (!room) return error(res, 404, 'Room not found')
      if (room.is_private && room.password !== password) return error(res, 403, 'Invalid password')

      const { error } = await supabase.from('room_participants').upsert({
        room_id: roomId, user_id: req.user!.id, role: 'listener'
      })

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Joined room')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async leave(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId } = req.params
      const { error } = await supabase.from('room_participants')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', req.user!.id)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Left room')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async updateRole(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId, userId } = req.params
      const { role } = req.body

      const { data: room } = await supabase.from('rooms').select('host_id').eq('id', roomId).single()
      if (!room || room.host_id !== req.user!.id) return error(res, 403, 'Not authorized')

      const { error } = await supabase.from('room_participants')
        .update({ role })
        .eq('room_id', roomId)
        .eq('user_id', userId)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Role updated')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
```

**src/controllers/notification.controller.ts**
```typescript
import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class NotificationController {
  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      const { page = 1, limit = 20, unread_only } = req.query
      let query = supabase.from('notifications').select('*', { count: 'exact' }).eq('user_id', req.user!.id)

      if (unread_only === 'true') query = query.eq('is_read', false)

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async markRead(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { error } = await supabase.from('notifications')
        .update({ is_read: true })
        .eq('id', id)
        .eq('user_id', req.user!.id)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Marked as read')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async markAllRead(req: AuthenticatedRequest, res: Response) {
    try {
      const { error } = await supabase.from('notifications')
        .update({ is_read: true })
        .eq('user_id', req.user!.id)
        .eq('is_read', false)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'All marked as read')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async registerPushToken(req: AuthenticatedRequest, res: Response) {
    try {
      const { token, platform } = req.body
      const { error } = await supabase.from('push_tokens').upsert({
        user_id: req.user!.id, token, platform
      })

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Token registered')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
```

**src/controllers/report.controller.ts**
```typescript
import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class ReportController {
  static async create(req: AuthenticatedRequest, res: Response) {
    try {
      const { reported_id, stream_id, post_id, reason, description } = req.body

      const { data, error: insertError } = await supabase.from('reports').insert({
        reporter_id: req.user!.id, reported_id, stream_id, post_id, reason, description
      }).select().single()

      if (insertError) return error(res, 400, insertError.message)
      return success(res, data, 'Report submitted')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
```

**src/controllers/admin.controller.ts**
```typescript
import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class AdminController {
  static async getDashboard(req: AuthenticatedRequest, res: Response) {
    try {
      const { data: stats } = await supabase.rpc('get_admin_dashboard_stats')
      return success(res, stats)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getUsers(req: AuthenticatedRequest, res: Response) {
    try {
      const { page = 1, limit = 20, search, status } = req.query
      let query = supabase.from('profiles').select('*', { count: 'exact' })

      if (search) query = query.or(`username.ilike.%${search}%,display_name.ilike.%${search}%`)
      if (status === 'banned') query = query.eq('is_banned', true)
      if (status === 'verified') query = query.eq('is_verified', true)

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async banUser(req: AuthenticatedRequest, res: Response) {
    try {
      const { userId } = req.params
      const { reason, duration_days } = req.body
      const banUntil = duration_days ? new Date(Date.now() + duration_days * 86400000).toISOString() : null

      const { error } = await supabase.from('profiles')
        .update({ is_banned: true, ban_reason: reason, ban_until: banUntil })
        .eq('id', userId)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'User banned')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async unbanUser(req: AuthenticatedRequest, res: Response) {
    try {
      const { userId } = req.params
      const { error } = await supabase.from('profiles')
        .update({ is_banned: false, ban_reason: null, ban_until: null })
        .eq('id', userId)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'User unbanned')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getReports(req: AuthenticatedRequest, res: Response) {
    try {
      const { page = 1, limit = 20, status = 'pending' } = req.query
      const { data, count } = await supabase
        .from('reports')
        .select('*, reporter:profiles!reports_reporter_id_fkey(*), reported:profiles!reports_reported_id_fkey(*)', { count: 'exact' })
        .eq('status', status)
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async resolveReport(req: AuthenticatedRequest, res: Response) {
    try {
      const { reportId } = req.params
      const { action, admin_notes } = req.body

      const { error } = await supabase.from('reports')
        .update({ status: 'resolved', admin_notes, resolved_at: new Date().toISOString() })
        .eq('id', reportId)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Report resolved')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getStreams(req: AuthenticatedRequest, res: Response) {
    try {
      const { page = 1, limit = 20, status } = req.query
      let query = supabase.from('streams').select('*, profiles!streams_host_id_fkey(*)', { count: 'exact' })

      if (status) query = query.eq('status', status)

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async banStream(req: AuthenticatedRequest, res: Response) {
    try {
      const { streamId } = req.params
      const { error } = await supabase.from('streams')
        .update({ status: 'banned' })
        .eq('id', streamId)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Stream banned')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getGifts(req: AuthenticatedRequest, res: Response) {
    try {
      const { data } = await supabase.from('gifts').select('*').order('sort_order')
      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async createGift(req: AuthenticatedRequest, res: Response) {
    try {
      const { name, description, image_url, animation_url, price_coins, diamond_value, category } = req.body
      const { data, error: insertError } = await supabase.from('gifts').insert({
        name, description, image_url, animation_url, price_coins, diamond_value, category
      }).select().single()

      if (insertError) return error(res, 400, insertError.message)
      return success(res, data, 'Gift created')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async updateGift(req: AuthenticatedRequest, res: Response) {
    try {
      const { giftId } = req.params
      const updates = req.body
      const { data, error: updateError } = await supabase.from('gifts')
        .update(updates)
        .eq('id', giftId)
        .select().single()

      if (updateError) return error(res, 400, updateError.message)
      return success(res, data, 'Gift updated')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getWithdrawals(req: AuthenticatedRequest, res: Response) {
    try {
      const { page = 1, limit = 20, status = 'pending' } = req.query
      const { data, count } = await supabase
        .from('wallet_transactions')
        .select('*, profiles!wallet_transactions_user_id_fkey(*)', { count: 'exact' })
        .eq('type', 'withdrawal')
        .eq('status', status)
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async processWithdrawal(req: AuthenticatedRequest, res: Response) {
    try {
      const { txId } = req.params
      const { status } = req.body

      const { error } = await supabase.from('wallet_transactions')
        .update({ status })
        .eq('id', txId)

      if (error) return error(res, 400, error.message)
      return success(res, null, 'Withdrawal updated')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
```

### 4.8 Routes

**src/routes/index.ts**
```typescript
import { Router } from 'express'
import authRoutes from './auth.routes'
import userRoutes from './user.routes'
import streamRoutes from './stream.routes'
import giftRoutes from './gift.routes'
import postRoutes from './post.routes'
import walletRoutes from './wallet.routes'
import roomRoutes from './room.routes'
import notificationRoutes from './notification.routes'
import reportRoutes from './report.routes'
import adminRoutes from './admin.routes'

const router = Router()

router.use('/auth', authRoutes)
router.use('/users', userRoutes)
router.use('/streams', streamRoutes)
router.use('/gifts', giftRoutes)
router.use('/posts', postRoutes)
router.use('/wallet', walletRoutes)
router.use('/rooms', roomRoutes)
router.use('/notifications', notificationRoutes)
router.use('/reports', reportRoutes)
router.use('/admin', adminRoutes)

export default router
```

**src/routes/auth.routes.ts**
```typescript
import { Router } from 'express'
import { body } from 'express-validator'
import { AuthController } from '../controllers/auth.controller'
import { authLimiter } from '../middleware/rateLimiter'

const router = Router()

router.post('/register', authLimiter, [
  body('email').isEmail().normalizeEmail(),
  body('password').isLength({ min: 6 }),
  body('username').isLength({ min: 3, max: 30 }).matches(/^[a-zA-Z0-9_]+$/)
], AuthController.register)

router.post('/login', authLimiter, [
  body('email').isEmail().normalizeEmail(),
  body('password').notEmpty()
], AuthController.login)

router.post('/social', authLimiter, [
  body('provider').isIn(['google', 'apple', 'facebook']),
  body('token').notEmpty()
], AuthController.socialLogin)

router.get('/me', AuthController.me)

export default router
```

**src/routes/user.routes.ts**
```typescript
import { Router } from 'express'
import { UserController } from '../controllers/user.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/search', authenticate, UserController.search)
router.get('/leaderboard', authenticate, UserController.getLeaderboard)
router.get('/:id', authenticate, UserController.getProfile)
router.put('/profile', authenticate, UserController.updateProfile)
router.post('/follow', authenticate, UserController.follow)
router.post('/unfollow', authenticate, UserController.unfollow)
router.get('/:id/followers', authenticate, UserController.getFollowers)
router.get('/:id/following', authenticate, UserController.getFollowing)

export default router
```

**src/routes/stream.routes.ts**
```typescript
import { Router } from 'express'
import { StreamController } from '../controllers/stream.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/', authenticate, StreamController.list)
router.post('/', authenticate, StreamController.create)
router.get('/:id', authenticate, StreamController.getById)
router.get('/:streamId/token', authenticate, StreamController.getToken)
router.post('/:streamId/join', authenticate, StreamController.join)
router.post('/:streamId/leave', authenticate, StreamController.leave)
router.post('/:streamId/end', authenticate, StreamController.end)
router.post('/:streamId/like', authenticate, StreamController.like)

export default router
```

**src/routes/gift.routes.ts**
```typescript
import { Router } from 'express'
import { GiftController } from '../controllers/gift.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/', authenticate, GiftController.list)
router.post('/send', authenticate, GiftController.send)
router.get('/transactions', authenticate, GiftController.getTransactions)

export default router
```

**src/routes/post.routes.ts**
```typescript
import { Router } from 'express'
import { PostController } from '../controllers/post.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/', authenticate, PostController.list)
router.post('/', authenticate, PostController.create)
router.get('/:id', authenticate, PostController.getById)
router.post('/:postId/like', authenticate, PostController.like)
router.post('/:postId/unlike', authenticate, PostController.unlike)
router.post('/:postId/comment', authenticate, PostController.comment)
router.delete('/:id', authenticate, PostController.delete)

export default router
```

**src/routes/wallet.routes.ts**
```typescript
import { Router } from 'express'
import { WalletController } from '../controllers/wallet.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/balance', authenticate, WalletController.getBalance)
router.get('/transactions', authenticate, WalletController.getTransactions)
router.post('/purchase', authenticate, WalletController.purchaseCoins)
router.post('/withdraw', authenticate, WalletController.withdraw)

export default router
```

**src/routes/room.routes.ts**
```typescript
import { Router } from 'express'
import { RoomController } from '../controllers/room.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/', authenticate, RoomController.list)
router.post('/', authenticate, RoomController.create)
router.post('/:roomId/join', authenticate, RoomController.join)
router.post('/:roomId/leave', authenticate, RoomController.leave)
router.put('/:roomId/participants/:userId/role', authenticate, RoomController.updateRole)

export default router
```

**src/routes/notification.routes.ts**
```typescript
import { Router } from 'express'
import { NotificationController } from '../controllers/notification.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/', authenticate, NotificationController.list)
router.put('/:id/read', authenticate, NotificationController.markRead)
router.put('/read-all', authenticate, NotificationController.markAllRead)
router.post('/push-token', authenticate, NotificationController.registerPushToken)

export default router
```

**src/routes/report.routes.ts**
```typescript
import { Router } from 'express'
import { ReportController } from '../controllers/report.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.post('/', authenticate, ReportController.create)

export default router
```

**src/routes/admin.routes.ts**
```typescript
import { Router } from 'express'
import { AdminController } from '../controllers/admin.controller'
import { authenticate, requireAdmin } from '../middleware/auth'

const router = Router()

router.use(authenticate, requireAdmin)

router.get('/dashboard', AdminController.getDashboard)
router.get('/users', AdminController.getUsers)
router.post('/users/:userId/ban', AdminController.banUser)
router.post('/users/:userId/unban', AdminController.unbanUser)
router.get('/reports', AdminController.getReports)
router.put('/reports/:reportId/resolve', AdminController.resolveReport)
router.get('/streams', AdminController.getStreams)
router.post('/streams/:streamId/ban', AdminController.banStream)
router.get('/gifts', AdminController.getGifts)
router.post('/gifts', AdminController.createGift)
router.put('/gifts/:giftId', AdminController.updateGift)
router.get('/withdrawals', AdminController.getWithdrawals)
router.put('/withdrawals/:txId', AdminController.processWithdrawal)

export default router
```

### 4.9 Socket.IO Setup

**src/socket/index.ts**
```typescript
import { Server as SocketServer } from 'socket.io'
import { Server } from 'http'
import { supabase } from '../config/database'
import { logger } from '../utils/logger'
import jwt from 'jsonwebtoken'

export const initSocket = (server: Server) => {
  const io = new SocketServer(server, {
    cors: { origin: '*', methods: ['GET', 'POST'] }
  })

  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth.token
      if (!token) return next(new Error('Authentication required'))

      const decoded = jwt.verify(token, process.env.JWT_SECRET!) as any
      socket.data.user = decoded
      next()
    } catch (err) {
      next(new Error('Invalid token'))
    }
  })

  io.on('connection', (socket) => {
    const userId = socket.data.user.id
    logger.info(`User connected: ${userId}`)
    socket.join(`user_${userId}`)

    socket.on('join-stream', async (streamId: string) => {
      socket.join(`stream_${streamId}`)

      const { data: messages } = await supabase
        .from('chat_messages')
        .select('*, profiles(user_id, username, avatar_url)')
        .eq('stream_id', streamId)
        .order('created_at', { ascending: false })
        .limit(50)

      socket.emit('chat-history', messages?.reverse() || [])
      socket.to(`stream_${streamId}`).emit('user-joined', { userId })
    })

    socket.on('leave-stream', (streamId: string) => {
      socket.leave(`stream_${streamId}`)
      socket.to(`stream_${streamId}`).emit('user-left', { userId })
    })

    socket.on('chat-message', async (data: { streamId: string, message: string }) => {
      const { streamId, message } = data

      await supabase.from('chat_messages').insert({
        stream_id: streamId, user_id: userId,
        message_type: 'text', content: message
      })

      io.to(`stream_${streamId}`).emit('chat-message', {
        userId, username: socket.data.user.email,
        message, timestamp: new Date().toISOString()
      })
    })

    socket.on('send-gift', async (data: { streamId: string, giftId: string, receiverId: string }) => {
      const { streamId, giftId, receiverId } = data

      const { data: gift } = await supabase.from('gifts').select('*').eq('id', giftId).single()
      if (!gift) return

      io.to(`stream_${streamId}`).emit('gift-received', {
        senderId: userId, receiverId, gift,
        timestamp: new Date().toISOString()
      })
    })

    socket.on('join-room', (roomId: string) => {
      socket.join(`room_${roomId}`)
      socket.to(`room_${roomId}`).emit('user-joined-room', { userId })
    })

    socket.on('leave-room', (roomId: string) => {
      socket.leave(`room_${roomId}`)
      socket.to(`room_${roomId}`).emit('user-left-room', { userId })
    })

    socket.on('room-message', (data: { roomId: string, message: string }) => {
      io.to(`room_${data.roomId}`).emit('room-message', {
        userId, message: data.message,
        timestamp: new Date().toISOString()
      })
    })

    socket.on('private-message', async (data: { to: string, message: string }) => {
      await supabase.from('private_messages').insert({
        sender_id: userId, receiver_id: data.to, content: data.message
      })

      io.to(`user_${data.to}`).emit('private-message', {
        from: userId, message: data.message,
        timestamp: new Date().toISOString()
      })
    })

    socket.on('disconnect', () => {
      logger.info(`User disconnected: ${userId}`)
    })
  })

  return io
}
```

### 4.10 Main Server File

**src/index.ts**
```typescript
import express from 'express'
import { createServer } from 'http'
import cors from 'cors'
import helmet from 'helmet'
import morgan from 'morgan'
import compression from 'compression'
import dotenv from 'dotenv'
import routes from './routes'
import { errorHandler } from './middleware/errorHandler'
import { apiLimiter } from './middleware/rateLimiter'
import { initSocket } from './socket'
import { LeaderboardService } from './services/leaderboard.service'
import { logger } from './utils/logger'

dotenv.config()

const app = express()
const server = createServer(app)
const io = initSocket(server)

app.use(helmet())
app.use(cors())
app.use(compression())
app.use(morgan('combined'))
app.use(express.json({ limit: '10mb' }))
app.use(express.urlencoded({ extended: true }))
app.use(apiLimiter)

app.use('/api/v1', routes)

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() })
})

app.use(errorHandler)

LeaderboardService.init()

const PORT = process.env.PORT || 3000
server.listen(PORT, () => {
  logger.info(`Server running on port ${PORT}`)
})

export { io }
```

### 4.11 Environment File
**`.env`**
```bash
PORT=3000
NODE_ENV=development
JWT_SECRET=your-super-secret-jwt-key-min-32-chars-change-in-production

SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

AGORA_APP_ID=your-agora-app-id
AGORA_APP_CERTIFICATE=your-agora-certificate

REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=

FIREBASE_PROJECT_ID=your-project-id
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nyour-key\n-----END PRIVATE KEY-----"
FIREBASE_CLIENT_EMAIL=firebase-adminsdk@your-project.iam.gserviceaccount.com
```

### 4.12 Run Commands
```bash
# Development
npm run dev

# Production build
npm run build
npm start

# Test API
curl http://localhost:3000/health
```

---

## 5. Flutter Mobile App

### 5.1 Project Setup
```bash
flutter create --org com.yourcompany rayzi_app
cd rayzi_app

# Add dependencies to pubspec.yaml
flutter pub add supabase_flutter agora_rtc_engine permission_handler \
  image_picker video_player chewie cached_network_image flutter_bloc \
  equatable dio socket_io_client shared_preferences flutter_local_notifications \
  firebase_messaging firebase_core google_sign_in sign_in_with_apple \
  flutter_screenutil shimmer flutter_staggered_grid_view intl \
  pull_to_refresh fluttertoast url_launcher package_info_plus \
  path_provider flutter_image_compress uuid

flutter pub get
```

### 5.2 pubspec.yaml
```yaml
name: rayzi_app
description: Rayzi Clone - Live Streaming App
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6
  supabase_flutter: ^2.0.0
  agora_rtc_engine: ^6.2.0
  permission_handler: ^11.0.0
  image_picker: ^1.0.0
  video_player: ^2.8.0
  chewie: ^1.7.0
  cached_network_image: ^3.3.0
  flutter_bloc: ^8.1.0
  equatable: ^2.0.0
  dio: ^5.4.0
  socket_io_client: ^2.0.0
  shared_preferences: ^2.2.0
  flutter_local_notifications: ^16.0.0
  firebase_messaging: ^14.7.0
  firebase_core: ^2.24.0
  google_sign_in: ^6.1.0
  sign_in_with_apple: ^5.0.0
  flutter_screenutil: ^5.9.0
  shimmer: ^3.0.0
  flutter_staggered_grid_view: ^0.7.0
  intl: ^0.18.0
  pull_to_refresh: ^2.0.0
  fluttertoast: ^8.2.0
  url_launcher: ^6.2.0
  package_info_plus: ^5.0.0
  path_provider: ^2.1.0
  flutter_image_compress: ^2.1.0
  uuid: ^4.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/icons/
    - assets/animations/
```

### 5.3 Directory Structure
```
lib/
├── main.dart
├── app.dart
├── config/
│   ├── constants.dart
│   ├── routes.dart
│   └── theme.dart
├── core/
│   ├── errors/
│   ├── usecases/
│   └── utils/
├── data/
│   ├── models/
│   ├── repositories/
│   └── datasources/
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── usecases/
├── presentation/
│   ├── blocs/
│   ├── screens/
│   └── widgets/
└── services/
    ├── api_service.dart
    ├── socket_service.dart
    ├── agora_service.dart
    ├── notification_service.dart
    └── storage_service.dart
```

### 5.4 Core Configuration

**lib/config/constants.dart**
```dart
class AppConstants {
  static const String appName = 'Rayzi';
  static const String apiBaseUrl = 'https://your-api.com/api/v1';
  static const String socketUrl = 'https://your-api.com';
  static const String supabaseUrl = 'https://your-project.supabase.co';
  static const String supabaseAnonKey = 'your-anon-key';
  static const String agoraAppId = 'your-agora-app-id';

  static const int paginationLimit = 20;
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration socketTimeout = Duration(seconds: 10);
}
```

**lib/config/theme.dart**
```dart
import 'package:flutter/material.dart'
import 'package:flutter_screenutil/flutter_screenutil.dart'

class AppTheme {
  static const Color primaryColor = Color(0xFF6C63FF);
  static const Color secondaryColor = Color(0xFF00BFA6);
  static const Color accentColor = Color(0xFFFF6584);
  static const Color darkBackground = Color(0xFF1A1A2E);
  static const Color cardBackground = Color(0xFF16213E);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color goldColor = Color(0xFFFFD700);

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: darkBackground,
    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: cardBackground,
      background: darkBackground,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: darkBackground,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
    ),
    cardTheme: CardTheme(
      color: cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: darkBackground,
      selectedItemColor: primaryColor,
      unselectedItemColor: textSecondary,
      type: BottomNavigationBarType.fixed,
    ),
  );
}
```

**lib/config/routes.dart**
```dart
import 'package:flutter/material.dart'
import '../presentation/screens/screens.dart'

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String profile = '/profile';
  static const String editProfile = '/edit-profile';
  static const String stream = '/stream';
  static const String createStream = '/create-stream';
  static const String postDetail = '/post-detail';
  static const String createPost = '/create-post';
  static const String room = '/room';
  static const String createRoom = '/create-room';
  static const String wallet = '/wallet';
  static const String giftStore = '/gift-store';
  static const String leaderboard = '/leaderboard';
  static const String search = '/search';
  static const String notifications = '/notifications';
  static const String settings = '/settings';
  static const String chat = '/chat';
  static const String userProfile = '/user-profile';

  static Map<String, WidgetBuilder> routes = {
    splash: (context) => const SplashScreen(),
    login: (context) => const LoginScreen(),
    register: (context) => const RegisterScreen(),
    home: (context) => const HomeScreen(),
    profile: (context) => const ProfileScreen(),
    editProfile: (context) => const EditProfileScreen(),
    createStream: (context) => const CreateStreamScreen(),
    wallet: (context) => const WalletScreen(),
    giftStore: (context) => const GiftStoreScreen(),
    leaderboard: (context) => const LeaderboardScreen(),
    search: (context) => const SearchScreen(),
    notifications: (context) => const NotificationsScreen(),
    settings: (context) => const SettingsScreen(),
  };
}
```

### 5.5 Services

**lib/services/api_service.dart**
```dart
import 'package:dio/dio.dart'
import 'package:shared_preferences/shared_preferences.dart'
import '../config/constants.dart'

class ApiService {
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConstants.apiBaseUrl,
    connectTimeout: AppConstants.apiTimeout,
    receiveTimeout: AppConstants.apiTimeout,
    headers: {'Content-Type': 'application/json'},
  ));

  static void init() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          // Handle token refresh or logout
        }
        return handler.next(error);
      },
    ));
  }

  static Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) {
    return _dio.get(path, queryParameters: queryParameters);
  }

  static Future<Response> post(String path, {dynamic data}) {
    return _dio.post(path, data: data);
  }

  static Future<Response> put(String path, {dynamic data}) {
    return _dio.put(path, data: data);
  }

  static Future<Response> delete(String path) {
    return _dio.delete(path);
  }
}
```

**lib/services/socket_service.dart**
```dart
import 'package:socket_io_client/socket_io_client.dart' as IO
import 'package:shared_preferences/shared_preferences.dart'
import '../config/constants.dart'

class SocketService {
  static IO.Socket? _socket;

  static Future<void> connect() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    _socket = IO.io(AppConstants.socketUrl, IO.OptionBuilder()
      .setTransports(['websocket'])
      .setAuth({'token': token})
      .enableAutoConnect()
      .build());

    _socket!.onConnect((_) => print('Socket connected'));
    _socket!.onDisconnect((_) => print('Socket disconnected'));
    _socket!.onError((err) => print('Socket error: $err'));
  }

  static void disconnect() {
    _socket?.disconnect();
  }

  static void joinStream(String streamId) {
    _socket?.emit('join-stream', streamId);
  }

  static void leaveStream(String streamId) {
    _socket?.emit('leave-stream', streamId);
  }

  static void sendChatMessage(String streamId, String message) {
    _socket?.emit('chat-message', {'streamId': streamId, 'message': message});
  }

  static void sendGift(String streamId, String giftId, String receiverId) {
    _socket?.emit('send-gift', {'streamId': streamId, 'giftId': giftId, 'receiverId': receiverId});
  }

  static void onChatMessage(Function(dynamic) callback) {
    _socket?.on('chat-message', callback);
  }

  static void onGiftReceived(Function(dynamic) callback) {
    _socket?.on('gift-received', callback);
  }

  static void onUserJoined(Function(dynamic) callback) {
    _socket?.on('user-joined', callback);
  }

  static void onUserLeft(Function(dynamic) callback) {
    _socket?.on('user-left', callback);
  }
}
```

**lib/services/agora_service.dart**
```dart
import 'package:agora_rtc_engine/agora_rtc_engine.dart'
import 'package:permission_handler/permission_handler.dart'
import '../config/constants.dart'

class AgoraService {
  static RtcEngine? _engine;

  static Future<void> initialize() async {
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: AppConstants.agoraAppId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));
  }

  static Future<void> requestPermissions() async {
    await [Permission.camera, Permission.microphone].request();
  }

  static Future<void> joinChannel(String channelName, String token, int uid, bool isHost) async {
    await _engine!.setClientRole(
      role: isHost ? ClientRoleType.clientRoleBroadcaster : ClientRoleType.clientRoleAudience
    );

    await _engine!.enableVideo();
    await _engine!.startPreview();

    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: const ChannelMediaOptions(),
    );
  }

  static Future<void> leaveChannel() async {
    await _engine?.leaveChannel();
    await _engine?.stopPreview();
  }

  static Future<void> dispose() async {
    await _engine?.release();
  }

  static RtcEngine? get engine => _engine;
}
```

**lib/services/notification_service.dart**
```dart
import 'package:firebase_messaging/firebase_messaging.dart'
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
import 'package:supabase_flutter/supabase_flutter.dart'

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    await _messaging.requestPermission();

    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings, iOS: iosSettings
    );

    await _localNotifications.initialize(initSettings);

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

    final token = await _messaging.getToken();
    if (token != null) {
      await _saveToken(token);
    }

    _messaging.onTokenRefresh.listen(_saveToken);
  }

  static Future<void> _saveToken(String token) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await Supabase.instance.client.from('push_tokens').upsert({
        'user_id': userId, 'token': token, 'platform': 'fcm'
      });
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    _showLocalNotification(message);
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'rayzi_channel', 'Rayzi Notifications',
      importance: Importance.high, priority: Priority.high
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title,
      message.notification?.body,
      details,
    );
  }
}

@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  print('Background message: ${message.messageId}');
}
```

**lib/services/storage_service.dart**
```dart
import 'package:supabase_flutter/supabase_flutter.dart'
import 'package:uuid/uuid.dart'

class StorageService {
  static final _client = Supabase.instance.client;
  static const _uuid = Uuid();

  static Future<String> uploadAvatar(String filePath, String userId) async {
    final fileName = 'avatar_$userId.jpg';
    await _client.storage.from('avatars').upload(fileName, filePath, fileOptions: const FileOptions(upsert: true));
    return _client.storage.from('avatars').getPublicUrl(fileName);
  }

  static Future<String> uploadStreamThumbnail(String filePath, String streamId) async {
    final fileName = 'thumb_$streamId.jpg';
    await _client.storage.from('stream-thumbnails').upload(fileName, filePath, fileOptions: const FileOptions(upsert: true));
    return _client.storage.from('stream-thumbnails').getPublicUrl(fileName);
  }

  static Future<String> uploadPostMedia(String filePath, String postId) async {
    final ext = filePath.split('.').last;
    final fileName = '${_uuid.v4()}.$ext';
    await _client.storage.from('post-media').upload(fileName, filePath);
    return _client.storage.from('post-media').getPublicUrl(fileName);
  }
}
```

### 5.6 BLoC Pattern

**lib/presentation/blocs/auth/auth_bloc.dart**
```dart
import 'package:flutter_bloc/flutter_bloc.dart'
import 'package:equatable/equatable.dart'
import 'package:supabase_flutter/supabase_flutter.dart'
import '../../../services/api_service.dart'

part 'auth_event.dart'
part 'auth_state.dart'

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onAuthCheckRequested(AuthCheckRequested event, Emitter<AuthState> emit) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      emit(AuthAuthenticated(session.user));
    } else {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onLoginRequested(AuthLoginRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final response = await ApiService.post('/auth/login', data: {
        'email': event.email, 'password': event.password
      });

      final token = response.data['data']['token'];
      final user = response.data['data']['user'];

      await Supabase.instance.client.auth.setSession(token);
      emit(AuthAuthenticated(User.fromJson(user)));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onRegisterRequested(AuthRegisterRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final response = await ApiService.post('/auth/register', data: {
        'email': event.email, 'password': event.password,
        'username': event.username, 'display_name': event.displayName
      });

      final token = response.data['data']['token'];
      final user = response.data['data']['user'];

      await Supabase.instance.client.auth.setSession(token);
      emit(AuthAuthenticated(User.fromJson(user)));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onLogoutRequested(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    await Supabase.instance.client.auth.signOut();
    emit(AuthUnauthenticated());
  }
}
```

**lib/presentation/blocs/auth/auth_event.dart**
```dart
part of 'auth_bloc.dart'

abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}
class AuthLoginRequested extends AuthEvent {
  final String email, password;
  AuthLoginRequested(this.email, this.password);
  @override
  List<Object?> get props => [email, password];
}
class AuthRegisterRequested extends AuthEvent {
  final String email, password, username, displayName;
  AuthRegisterRequested(this.email, this.password, this.username, this.displayName);
  @override
  List<Object?> get props => [email, password, username, displayName];
}
class AuthLogoutRequested extends AuthEvent {}
```

**lib/presentation/blocs/auth/auth_state.dart**
```dart
part of 'auth_bloc.dart'

abstract class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class AuthAuthenticated extends AuthState {
  final User user;
  AuthAuthenticated(this.user);
  @override
  List<Object?> get props => [user];
}
class AuthUnauthenticated extends AuthState {}
class AuthError extends AuthState {
  final String message;
  AuthError(this.message);
  @override
  List<Object?> get props => [message];
}
```

### 5.7 Key Screens

**lib/presentation/screens/splash_screen.dart**
```dart
import 'package:flutter/material.dart'
import 'package:flutter_bloc/flutter_bloc.dart'
import '../../config/routes.dart'
import '../blocs/auth/auth_bloc.dart'

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AuthBloc>().add(AuthCheckRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          Navigator.pushReplacementNamed(context, AppRoutes.home);
        } else if (state is AuthUnauthenticated) {
          Navigator.pushReplacementNamed(context, AppRoutes.login);
        }
      },
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.live_tv, size: 80, color: Theme.of(context).primaryColor),
              const SizedBox(height: 20),
              const Text('Rayzi', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
```

**lib/presentation/screens/login_screen.dart**
```dart
import 'package:flutter/material.dart'
import 'package:flutter_bloc/flutter_bloc.dart'
import 'package:flutter_screenutil/flutter_screenutil.dart'
import '../../config/routes.dart'
import '../blocs/auth/auth_bloc.dart'
import '../widgets/custom_button.dart'
import '../widgets/custom_textfield.dart'

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 40.h),
              Text('Welcome Back', style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 8.h),
              Text('Sign in to continue', style: TextStyle(fontSize: 16.sp, color: Colors.grey)),
              SizedBox(height: 40.h),
              CustomTextField(
                controller: _emailController,
                hint: 'Email',
                prefixIcon: Icons.email,
                keyboardType: TextInputType.emailAddress,
              ),
              SizedBox(height: 16.h),
              CustomTextField(
                controller: _passwordController,
                hint: 'Password',
                prefixIcon: Icons.lock,
                obscureText: true,
              ),
              SizedBox(height: 24.h),
              BlocConsumer<AuthBloc, AuthState>(
                listener: (context, state) {
                  if (state is AuthAuthenticated) {
                    Navigator.pushReplacementNamed(context, AppRoutes.home);
                  } else if (state is AuthError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(state.message)),
                    );
                  }
                },
                builder: (context, state) {
                  return CustomButton(
                    text: state is AuthLoading ? 'Loading...' : 'Sign In',
                    onPressed: state is AuthLoading ? null : () {
                      context.read<AuthBloc>().add(
                        AuthLoginRequested(_emailController.text, _passwordController.text),
                      );
                    },
                  );
                },
              ),
              SizedBox(height: 16.h),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.register),
                  child: const Text('Don\'t have an account? Sign Up'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**lib/presentation/screens/home_screen.dart**
```dart
import 'package:flutter/material.dart'
import 'package:flutter_screenutil/flutter_screenutil.dart'
import '../../config/routes.dart'
import 'live_tab.dart'
import 'explore_tab.dart'
import 'rooms_tab.dart'
import 'messages_tab.dart'
import 'profile_tab.dart'

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _tabs = [
    const LiveTab(),
    const ExploreTab(),
    const RoomsTab(),
    const MessagesTab(),
    const ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.live_tv), label: 'Live'),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Explore'),
          BottomNavigationBarItem(icon: Icon(Icons.meeting_room), label: 'Rooms'),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Messages'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      floatingActionButton: _currentIndex == 0
        ? FloatingActionButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.createStream),
            child: const Icon(Icons.videocam),
          )
        : null,
    );
  }
}
```

**lib/presentation/screens/live_tab.dart**
```dart
import 'package:flutter/material.dart'
import 'package:flutter_screenutil/flutter_screenutil.dart'
import 'package:cached_network_image/cached_network_image.dart'
import '../../services/api_service.dart'
import '../../config/routes.dart'

class LiveTab extends StatefulWidget {
  const LiveTab({super.key});

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  List<dynamic> _streams = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStreams();
  }

  Future<void> _loadStreams() async {
    try {
      final response = await ApiService.get('/streams', queryParameters: {'status': 'live'});
      setState(() {
        _streams = response.data['data'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Streams'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.search),
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.notifications),
          ),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadStreams,
            child: _streams.isEmpty
              ? const Center(child: Text('No live streams'))
              : GridView.builder(
                  padding: EdgeInsets.all(12.w),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 12.w,
                    mainAxisSpacing: 12.h,
                  ),
                  itemCount: _streams.length,
                  itemBuilder: (context, index) {
                    final stream = _streams[index];
                    return GestureDetector(
                      onTap: () => Navigator.pushNamed(
                        context, AppRoutes.stream,
                        arguments: stream,
                      ),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CachedNetworkImage(
                                    imageUrl: stream['thumbnail_url'] ?? 'https://via.placeholder.com/300',
                                    fit: BoxFit.cover,
                                  ),
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(4.r),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6.w, height: 6.h,
                                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                          ),
                                          SizedBox(width: 4.w),
                                          Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10.sp)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4.r),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.visibility, size: 14, color: Colors.white),
                                          SizedBox(width: 4.w),
                                          Text('${stream['current_viewers'] ?? 0}', style: TextStyle(color: Colors.white, fontSize: 10.sp)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8.w),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stream['title'] ?? 'Untitled Stream',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(height: 4.h),
                                  Text(
                                    stream['profiles']?['display_name'] ?? 'Unknown',
                                    style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
    );
  }
}
```

**lib/presentation/screens/stream_screen.dart**
```dart
import 'package:flutter/material.dart'
import 'package:agora_rtc_engine/agora_rtc_engine.dart'
import 'package:flutter_screenutil/flutter_screenutil.dart'
import '../../services/agora_service.dart'
import '../../services/socket_service.dart'
import '../../services/api_service.dart'

class StreamScreen extends StatefulWidget {
  final Map<String, dynamic> stream;
  const StreamScreen({super.key, required this.stream});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  bool _isLoading = true;
  String? _token;
  bool _isHost = false;
  final _chatController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _initializeStream();
  }

  Future<void> _initializeStream() async {
    await AgoraService.initialize();
    await AgoraService.requestPermissions();

    final response = await ApiService.get('/streams/${widget.stream['id']}/token');
    _token = response.data['data']['token'];
    _isHost = response.data['data']['is_host'];

    final uid = int.parse(widget.stream['host_id'].toString().replaceAll('-', '').substring(0, 8), radix: 16);

    await AgoraService.joinChannel(
      widget.stream['channel_name'],
      _token!,
      uid,
      _isHost,
    );

    await SocketService.connect();
    SocketService.joinStream(widget.stream['id']);

    SocketService.onChatMessage((data) {
      setState(() => _messages.add(data));
    });

    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    SocketService.leaveStream(widget.stream['id']);
    AgoraService.leaveChannel();
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              // Video view
              AgoraVideoView(
                controller: VideoViewController(
                  rtcEngine: AgoraService.engine!,
                  canvas: const VideoCanvas(uid: 0),
                ),
              ),
              // Chat overlay
              Positioned(
                bottom: 80.h,
                left: 16.w,
                right: 16.w,
                child: Container(
                  height: 200.h,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: ListView.builder(
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[_messages.length - 1 - index];
                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                        child: Text(
                          '${msg['username']}: ${msg['message']}',
                          style: TextStyle(color: Colors.white, fontSize: 12.sp),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Chat input
              Positioned(
                bottom: 16.h,
                left: 16.w,
                right: 16.w,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Say something...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.black54,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24.r)),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: () {
                        if (_chatController.text.isNotEmpty) {
                          SocketService.sendChatMessage(widget.stream['id'], _chatController.text);
                          _chatController.clear();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.card_giftcard, color: Colors.amber),
                      onPressed: () => _showGiftSheet(),
                    ),
                  ],
                ),
              ),
              // Close button
              Positioned(
                top: 40.h,
                right: 16.w,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
    );
  }

  void _showGiftSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        height: 300.h,
        padding: EdgeInsets.all(16.w),
        child: Column(
          children: [
            Text('Send Gift', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 16.h),
            Expanded(
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4, childAspectRatio: 0.8,
                ),
                itemCount: 6,
                itemBuilder: (context, index) {
                  final gifts = ['Rose', 'Heart', 'Teddy', 'Crown', 'Car', 'Yacht'];
                  final prices = [10, 50, 100, 500, 1000, 5000];
                  return GestureDetector(
                    onTap: () {
                      SocketService.sendGift(
                        widget.stream['id'],
                        'gift_$index',
                        widget.stream['host_id'],
                      );
                      Navigator.pop(context);
                    },
                    child: Column(
                      children: [
                        Icon(Icons.card_giftcard, size: 40.w, color: Colors.amber),
                        Text(gifts[index], style: TextStyle(fontSize: 12.sp)),
                        Text('${prices[index]} coins', style: TextStyle(fontSize: 10.sp, color: Colors.grey)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**lib/presentation/screens/profile_tab.dart**
```dart
import 'package:flutter/material.dart'
import 'package:flutter_bloc/flutter_bloc.dart'
import 'package:flutter_screenutil/flutter_screenutil.dart'
import 'package:cached_network_image/cached_network_image.dart'
import '../../config/routes.dart'
import '../blocs/auth/auth_bloc.dart'

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ],
      ),
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state is AuthAuthenticated) {
            return SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50.r,
                    backgroundImage: CachedNetworkImageProvider(
                      state.user.userMetadata?['avatar_url'] ?? '',
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    state.user.userMetadata?['display_name'] ?? 'User',
                    style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '@${state.user.userMetadata?['username'] ?? 'user'}',
                    style: TextStyle(fontSize: 16.sp, color: Colors.grey),
                  ),
                  SizedBox(height: 24.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStat('0', 'Posts'),
                      _buildStat('0', 'Followers'),
                      _buildStat('0', 'Following'),
                    ],
                  ),
                  SizedBox(height: 24.h),
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet),
                    title: const Text('Wallet'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, AppRoutes.wallet),
                  ),
                  ListTile(
                    leading: const Icon(Icons.emoji_events),
                    title: const Text('Leaderboard'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, AppRoutes.leaderboard),
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Edit Profile'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, AppRoutes.editProfile),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Logout', style: TextStyle(color: Colors.red)),
                    onTap: () {
                      context.read<AuthBloc>().add(AuthLogoutRequested());
                    },
                  ),
                ],
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
      ],
    );
  }
}
```

## 6. Android Build Setup

### 6.1 android/app/build.gradle
```gradle
plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
    id "com.google.gms.google-services"
}

def localProperties = new Properties()
def localPropertiesFile = rootProject.file('local.properties')
if (localPropertiesFile.exists()) {
    localPropertiesFile.withReader('UTF-8') { reader ->
        localProperties.load(reader)
    }
}

def flutterVersionCode = localProperties.getProperty('flutter.versionCode')
if (flutterVersionCode == null) {
    flutterVersionCode = '1'
}

def flutterVersionName = localProperties.getProperty('flutter.versionName')
if (flutterVersionName == null) {
    flutterVersionName = '1.0'
}

android {
    namespace "com.yourcompany.rayzi_app"
    compileSdkVersion flutter.compileSdkVersion
    ndkVersion flutter.ndkVersion

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = '1.8'
    }

    sourceSets {
        main.java.srcDirs += 'src/main/kotlin'
    }

    defaultConfig {
        applicationId "com.yourcompany.rayzi_app"
        minSdkVersion 21
        targetSdkVersion flutter.targetSdkVersion
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
        multiDexEnabled true
    }

    signingConfigs {
        release {
            keyAlias localProperties.getProperty('keyAlias')
            keyPassword localProperties.getProperty('keyPassword')
            storeFile localProperties.getProperty('storeFile') ? file(localProperties.getProperty('storeFile')) : null
            storePassword localProperties.getProperty('storePassword')
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
        debug {
            signingConfig signingConfigs.debug
        }
    }
}

flutter {
    source '../..'
}

dependencies {
    implementation "org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.8.22"
    implementation 'androidx.multidex:multidex:2.0.1'
    implementation platform('com.google.firebase:firebase-bom:32.7.0')
    implementation 'com.google.firebase:firebase-analytics'
    implementation 'com.google.firebase:firebase-messaging'
}
```

### 6.2 android/build.gradle
```gradle
buildscript {
    ext.kotlin_version = '1.8.22'
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.1.0'
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version"
        classpath 'com.google.gms:google-services:4.4.0'
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.buildDir = '../build'
subprojects {
    project.buildDir = "${rootProject.buildDir}/${project.name}"
    project.evaluationDependsOn(':app')
}

tasks.register("clean", Delete) {
    delete rootProject.buildDir
}
```

### 6.3 android/app/proguard-rules.pro
```proguard
# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Agora
-keep class io.agora.**{*;}
-keep class com.agora.**{*;}
-dontwarn io.agora.**

# Supabase
-keep class io.github.jan.supabase.** { *; }
-keep class io.ktor.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# General
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod
```

### 6.4 android/app/src/main/AndroidManifest.xml
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.BLUETOOTH"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.READ_PHONE_STATE"/>

    <application
        android:label="Rayzi"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="false"
        android:networkSecurityConfig="@xml/network_security_config">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme"/>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2"/>

        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="rayzi_channel"/>

        <service
            android:name="com.google.firebase.messaging.FirebaseMessagingService"
            android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT"/>
            </intent-filter>
        </service>
    </application>
</manifest>
```

### 6.5 android/app/src/main/res/xml/network_security_config.xml
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system"/>
        </trust-anchors>
    </base-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">10.0.2.2</domain>
        <domain includeSubdomains="true">localhost</domain>
    </domain-config>
</network-security-config>
```

### 6.6 android/local.properties (add to .gitignore)
```properties
flutter.sdk=/path/to/flutter
sdk.dir=/path/to/android/sdk
keyAlias=rayzi
keyPassword=your-key-password
storeFile=../keystore/rayzi.jks
storePassword=your-store-password
```

### 6.7 Keystore Generation
```bash
# Create keystore directory
mkdir -p android/keystore

# Generate release keystore
keytool -genkey -v -keystore android/keystore/rayzi.jks -keyalg RSA -keysize 2048 -validity 10000 -alias rayzi

# Generate upload key for Play Store (App Signing)
keytool -genkey -v -keystore android/keystore/upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### 6.8 Build Commands
```bash
# Debug build
flutter build apk --debug

# Release build
flutter build apk --release

# App bundle for Play Store
flutter build appbundle --release

# Install on device
flutter install
```

---

## 7. Admin Panel (Flutter Web)

### 7.1 Setup
```bash
flutter create --org com.yourcompany rayzi_admin --platforms web
cd rayzi_admin

# Add dependencies
flutter pub add fl_chart data_table_2 file_picker url_strategy
flutter pub get
```

### 7.2 pubspec.yaml
```yaml
name: rayzi_admin
description: Rayzi Admin Dashboard
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6
  supabase_flutter: ^2.0.0
  dio: ^5.4.0
  flutter_bloc: ^8.1.0
  equatable: ^2.0.0
  fl_chart: ^0.66.0
  data_table_2: ^2.5.0
  file_picker: ^6.1.0
  url_strategy: ^0.2.0
  cached_network_image: ^3.3.0
  intl: ^0.18.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
```

### 7.3 Main Entry
**lib/main.dart**
```dart
import 'package:flutter/material.dart'
import 'package:url_strategy/url_strategy.dart'
import 'package:supabase_flutter/supabase_flutter.dart'
import 'app.dart'

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setPathUrlStrategy();

  await Supabase.initialize(
    url: 'https://your-project.supabase.co',
    anonKey: 'your-anon-key',
  );

  runApp(const AdminApp());
}
```

**lib/app.dart**
```dart
import 'package:flutter/material.dart'
import 'package:flutter_bloc/flutter_bloc.dart'
import 'presentation/screens/login_screen.dart'
import 'presentation/screens/dashboard_screen.dart'
import 'presentation/blocs/auth/auth_bloc.dart'

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AuthBloc(),
      child: MaterialApp(
        title: 'Rayzi Admin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const AdminLoginScreen(),
          '/dashboard': (context) => const DashboardScreen(),
          '/users': (context) => const UsersScreen(),
          '/streams': (context) => const StreamsScreen(),
          '/reports': (context) => const ReportsScreen(),
          '/gifts': (context) => const GiftsScreen(),
          '/withdrawals': (context) => const WithdrawalsScreen(),
        },
      ),
    );
  }
}
```

### 7.4 Dashboard Screen
**lib/presentation/screens/dashboard_screen.dart**
```dart
import 'package:flutter/material.dart'
import 'package:fl_chart/fl_chart.dart'
import 'package:supabase_flutter/supabase_flutter.dart'
import '../widgets/admin_drawer.dart'
import '../widgets/stats_card.dart'

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final response = await Supabase.instance.client.rpc('get_admin_dashboard_stats');
    setState(() {
      _stats = response;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      drawer: const AdminDrawer(),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Overview', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    StatsCard(
                      title: 'Total Users',
                      value: '${_stats?['total_users'] ?? 0}',
                      icon: Icons.people,
                      color: Colors.blue,
                    ),
                    StatsCard(
                      title: 'Live Streams',
                      value: '${_stats?['live_streams'] ?? 0}',
                      icon: Icons.live_tv,
                      color: Colors.red,
                    ),
                    StatsCard(
                      title: 'Total Gifts Sent',
                      value: '${_stats?['total_gifts'] ?? 0}',
                      icon: Icons.card_giftcard,
                      color: Colors.amber,
                    ),
                    StatsCard(
                      title: 'Pending Reports',
                      value: '${_stats?['pending_reports'] ?? 0}',
                      icon: Icons.report,
                      color: Colors.orange,
                    ),
                    StatsCard(
                      title: 'Pending Withdrawals',
                      value: '${_stats?['pending_withdrawals'] ?? 0}',
                      icon: Icons.account_balance_wallet,
                      color: Colors.green,
                    ),
                    StatsCard(
                      title: 'Revenue (Coins)',
                      value: '${_stats?['total_revenue'] ?? 0}',
                      icon: Icons.attach_money,
                      color: Colors.purple,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text('Activity Chart', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                SizedBox(
                  height: 300,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: true),
                      titlesData: const FlTitlesData(show: true),
                      borderData: FlBorderData(show: true),
                      lineBarsData: [
                        LineChartBarData(
                          spots: const [
                            FlSpot(0, 3), FlSpot(1, 5), FlSpot(2, 4),
                            FlSpot(3, 7), FlSpot(4, 6), FlSpot(5, 8),
                            FlSpot(6, 9),
                          ],
                          isCurved: true,
                          color: Colors.indigo,
                          barWidth: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
```

### 7.5 Users Management Screen
**lib/presentation/screens/users_screen.dart**
```dart
import 'package:flutter/material.dart'
import 'package:data_table_2/data_table_2.dart'
import 'package:supabase_flutter/supabase_flutter.dart'
import '../widgets/admin_drawer.dart'

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<dynamic> _users = [];
  bool _isLoading = true;
  int _page = 0;
  final int _rowsPerPage = 25;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final response = await Supabase.instance.client
      .from('profiles')
      .select('*')
      .range(_page * _rowsPerPage, (_page + 1) * _rowsPerPage - 1)
      .order('created_at', ascending: false);

    setState(() {
      _users = response;
      _isLoading = false;
    });
  }

  Future<void> _banUser(String userId, String reason) async {
    await Supabase.instance.client.from('profiles').update({
      'is_banned': true, 'ban_reason': reason
    }).eq('id', userId);
    _loadUsers();
  }

  Future<void> _unbanUser(String userId) async {
    await Supabase.instance.client.from('profiles').update({
      'is_banned': false, 'ban_reason': null, 'ban_until': null
    }).eq('id', userId);
    _loadUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Management')),
      drawer: const AdminDrawer(),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16),
            child: DataTable2(
              columnSpacing: 12,
              horizontalMargin: 12,
              minWidth: 800,
              columns: const [
                DataColumn2(label: Text('User'), size: ColumnSize.L),
                DataColumn2(label: Text('Email')),
                DataColumn2(label: Text('Status')),
                DataColumn2(label: Text('Coins')),
                DataColumn2(label: Text('Diamonds')),
                DataColumn2(label: Text('Joined')),
                DataColumn2(label: Text('Actions'), size: ColumnSize.S),
              ],
              rows: _users.map((user) {
                return DataRow(
                  cells: [
                    DataCell(Row(
                      children: [
                        CircleAvatar(
                          backgroundImage: NetworkImage(user['avatar_url'] ?? ''),
                          radius: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(user['display_name'] ?? user['username'] ?? 'Unknown'),
                      ],
                    )),
                    DataCell(Text(user['email'] ?? 'N/A')),
                    DataCell(
                      user['is_banned'] == true
                        ? Chip(label: const Text('Banned'), backgroundColor: Colors.red[100])
                        : Chip(label: const Text('Active'), backgroundColor: Colors.green[100])
                    ),
                    DataCell(Text('${user['coins'] ?? 0}')),
                    DataCell(Text('${user['diamonds'] ?? 0}')),
                    DataCell(Text(user['created_at']?.toString().split('T')[0] ?? 'N/A')),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (user['is_banned'] != true)
                          IconButton(
                            icon: const Icon(Icons.block, color: Colors.red),
                            onPressed: () => _showBanDialog(user['id']),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            onPressed: () => _unbanUser(user['id']),
                          ),
                        IconButton(
                          icon: const Icon(Icons.visibility),
                          onPressed: () {},
                        ),
                      ],
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
    );
  }

  void _showBanDialog(String userId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ban User'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Reason'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _banUser(userId, controller.text);
              Navigator.pop(context);
            },
            child: const Text('Ban'),
          ),
        ],
      ),
    );
  }
}
```

### 7.6 Admin Drawer
**lib/presentation/widgets/admin_drawer.dart**
```dart
import 'package:flutter/material.dart'

class AdminDrawer extends StatelessWidget {
  const AdminDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rayzi Admin', style: TextStyle(color: Colors.white, fontSize: 24)),
                Text('Management Panel', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () => Navigator.pushNamed(context, '/dashboard'),
          ),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Users'),
            onTap: () => Navigator.pushNamed(context, '/users'),
          ),
          ListTile(
            leading: const Icon(Icons.live_tv),
            title: const Text('Streams'),
            onTap: () => Navigator.pushNamed(context, '/streams'),
          ),
          ListTile(
            leading: const Icon(Icons.report),
            title: const Text('Reports'),
            onTap: () => Navigator.pushNamed(context, '/reports'),
          ),
          ListTile(
            leading: const Icon(Icons.card_giftcard),
            title: const Text('Gifts'),
            onTap: () => Navigator.pushNamed(context, '/gifts'),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: const Text('Withdrawals'),
            onTap: () => Navigator.pushNamed(context, '/withdrawals'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.pushReplacementNamed(context, '/'),
          ),
        ],
      ),
    );
  }
}
```

### 7.7 Build & Deploy
```bash
# Build for web
flutter build web --release

# Deploy to Firebase Hosting
firebase deploy --only hosting

# Or deploy to Netlify
netlify deploy --prod --dir=build/web

# Or deploy to Vercel
vercel --prod
```

---

## 8. Docker & Deployment

### 8.1 Backend Dockerfile
**rayzi-backend/Dockerfile**
```dockerfile
# Build stage
FROM node:18-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Production stage
FROM node:18-alpine

WORKDIR /app
ENV NODE_ENV=production

COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

COPY --from=builder /app/dist ./dist

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

USER node

CMD ["node", "dist/index.js"]
```

### 8.2 Backend .dockerignore
**rayzi-backend/.dockerignore**
```
node_modules
npm-debug.log
Dockerfile
.dockerignore
.git
.gitignore
README.md
.env
.env.local
.env.development
.env.test
.env.production
coverage
.nyc_output
.vscode
.idea
dist
```

### 8.3 docker-compose.yml (Root)
**docker-compose.yml**
```yaml
version: '3.8'

services:
  api:
    build: ./rayzi-backend
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - PORT=3000
      - SUPABASE_URL=${SUPABASE_URL}
      - SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}
      - JWT_SECRET=${JWT_SECRET}
      - AGORA_APP_ID=${AGORA_APP_ID}
      - AGORA_APP_CERTIFICATE=${AGORA_APP_CERTIFICATE}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID}
      - FIREBASE_PRIVATE_KEY=${FIREBASE_PRIVATE_KEY}
      - FIREBASE_CLIENT_EMAIL=${FIREBASE_CLIENT_EMAIL}
    depends_on:
      - redis
    restart: unless-stopped
    networks:
      - rayzi-network

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    restart: unless-stopped
    networks:
      - rayzi-network

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
    depends_on:
      - api
    restart: unless-stopped
    networks:
      - rayzi-network

volumes:
  redis-data:

networks:
  rayzi-network:
    driver: bridge
```

### 8.4 Nginx Configuration
**nginx/nginx.conf**
```nginx
events {
    worker_connections 1024;
}

http {
    upstream api {
        server api:3000;
    }

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=auth_limit:10m rate=1r/s;

    server {
        listen 80;
        server_name api.yourdomain.com;

        # Redirect HTTP to HTTPS
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name api.yourdomain.com;

        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        # Gzip compression
        gzip on;
        gzip_vary on;
        gzip_min_length 1024;
        gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

        location / {
            proxy_pass http://api;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            proxy_read_timeout 86400;
        }

        location /api/v1/auth/ {
            limit_req zone=auth_limit burst=5 nodelay;
            proxy_pass http://api;
        }

        location /api/v1/ {
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://api;
        }
    }
}
```

### 8.5 Deploy Commands
```bash
# Build and start all services
docker-compose up -d --build

# View logs
docker-compose logs -f api

# Scale API instances
docker-compose up -d --scale api=3

# Update deployment
docker-compose pull && docker-compose up -d

# Stop all
docker-compose down

# Clean up
docker system prune -f
```

### 8.6 Environment File for Production
**.env.production**
```bash
# Server
NODE_ENV=production
PORT=3000

# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

# Security
JWT_SECRET=your-256-bit-secret-key-here-min-32-chars

# Agora
AGORA_APP_ID=your-agora-app-id
AGORA_APP_CERTIFICATE=your-agora-certificate

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# Firebase
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
FIREBASE_CLIENT_EMAIL=firebase-adminsdk@your-project.iam.gserviceaccount.com
```

---

## 9. CI/CD Pipeline

### 9.1 GitHub Actions — Backend
**.github/workflows/backend.yml**
```yaml
name: Backend CI/CD

on:
  push:
    branches: [main, develop]
    paths: ['rayzi-backend/**']
  pull_request:
    branches: [main]
    paths: ['rayzi-backend/**']

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./rayzi-backend

    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
          cache-dependency-path: './rayzi-backend/package-lock.json'

      - name: Install dependencies
        run: npm ci

      - name: Run linter
        run: npm run lint

      - name: Run tests
        run: npm test
        env:
          NODE_ENV: test
          SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
          SUPABASE_SERVICE_ROLE_KEY: ${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}
          JWT_SECRET: test-secret-key-for-ci-only

      - name: Build
        run: npm run build

  deploy:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    defaults:
      run:
        working-directory: ./rayzi-backend

    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
          cache-dependency-path: './rayzi-backend/package-lock.json'

      - name: Install dependencies
        run: npm ci

      - name: Build
        run: npm run build

      - name: Deploy to VPS
        uses: appleboy/ssh-action@v1.0.0
        with:
          host: ${{ secrets.VPS_HOST }}
          username: ${{ secrets.VPS_USER }}
          key: ${{ secrets.VPS_SSH_KEY }}
          script: |
            cd /opt/rayzi
            git pull origin main
            docker-compose up -d --build api
            docker system prune -f
```

### 9.2 GitHub Actions — Flutter App
**.github/workflows/flutter.yml**
```yaml
name: Flutter CI/CD

on:
  push:
    branches: [main, develop]
    paths: ['rayzi_app/**']
  pull_request:
    branches: [main]
    paths: ['rayzi_app/**']

jobs:
  analyze:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./rayzi_app

    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'
          channel: 'stable'

      - name: Get dependencies
        run: flutter pub get

      - name: Analyze
        run: flutter analyze

      - name: Run tests
        run: flutter test

  build-android:
    needs: analyze
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    defaults:
      run:
        working-directory: ./rayzi_app

    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'
          channel: 'stable'

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'

      - name: Get dependencies
        run: flutter pub get

      - name: Build APK
        run: flutter build apk --release

      - name: Build App Bundle
        run: flutter build appbundle --release

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: release-apk
          path: rayzi_app/build/app/outputs/flutter-apk/app-release.apk

      - name: Upload AAB
        uses: actions/upload-artifact@v4
        with:
          name: release-aab
          path: rayzi_app/build/app/outputs/bundle/release/app-release.aab

  build-ios:
    needs: analyze
    runs-on: macos-latest
    if: github.ref == 'refs/heads/main'
    defaults:
      run:
        working-directory: ./rayzi_app

    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'
          channel: 'stable'

      - name: Get dependencies
        run: flutter pub get

      - name: Build iOS
        run: flutter build ios --release --no-codesign
```

### 9.3 GitHub Actions — Admin Panel
**.github/workflows/admin.yml**
```yaml
name: Admin Panel CI/CD

on:
  push:
    branches: [main]
    paths: ['rayzi_admin/**']

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./rayzi_admin

    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'
          channel: 'stable'

      - name: Get dependencies
        run: flutter pub get

      - name: Build web
        run: flutter build web --release

      - name: Deploy to Firebase
        uses: FirebaseExtended/action-hosting-deploy@v0
        with:
          repoToken: ${{ secrets.GITHUB_TOKEN }}
          firebaseServiceAccount: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
          channelId: live
          projectId: your-project-id
```

### 9.4 GitHub Secrets Setup
In your GitHub repo, go to Settings > Secrets and variables > Actions, add:

| Secret Name | Value |
|-------------|-------|
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Your Supabase service role key |
| `VPS_HOST` | Your server IP/domain |
| `VPS_USER` | SSH username (e.g., root, ubuntu) |
| `VPS_SSH_KEY` | Private SSH key for deployment |
| `FIREBASE_SERVICE_ACCOUNT` | Firebase service account JSON |

---

## 10. Testing & QA

### 10.1 Backend Testing

**Install testing dependencies**
```bash
cd rayzi-backend
npm install -D jest @types/jest supertest @types/supertest
```

**jest.config.js**
```javascript
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/__tests__/**/*.test.ts'],
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.d.ts',
    '!src/index.ts',
  ],
  coverageDirectory: 'coverage',
  coverageReporters: ['text', 'lcov', 'html'],
};
```

**src/__tests__/auth.test.ts**
```typescript
import request from 'supertest'
import express from 'express'
import routes from '../routes'

const app = express()
app.use(express.json())
app.use('/api/v1', routes)

describe('Auth Endpoints', () => {
  it('POST /auth/register - should create a new user', async () => {
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({
        email: 'test@example.com',
        password: 'password123',
        username: 'testuser',
        display_name: 'Test User'
      })

    expect(res.status).toBe(201)
    expect(res.body.success).toBe(true)
    expect(res.body.data).toHaveProperty('token')
  })

  it('POST /auth/login - should authenticate user', async () => {
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({
        email: 'test@example.com',
        password: 'password123'
      })

    expect(res.status).toBe(200)
    expect(res.body.success).toBe(true)
  })

  it('POST /auth/login - should reject invalid credentials', async () => {
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({
        email: 'test@example.com',
        password: 'wrongpassword'
      })

    expect(res.status).toBe(401)
    expect(res.body.success).toBe(false)
  })
})
```

**Run tests**
```bash
npm test
npm run test:coverage
```

### 10.2 Flutter Testing

**test/widget_test.dart**
```dart
import 'package:flutter/material.dart'
import 'package:flutter_test/flutter_test.dart'
import 'package:rayzi_app/main.dart'

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Login screen has email and password fields', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    // Navigate to login if not initial route
    expect(find.byType(TextField), findsWidgets);
  });
}
```

**test/unit_test.dart**
```dart
import 'package:flutter_test/flutter_test.dart'

void main() {
  group('Utility Functions', () {
    test('formatNumber formats thousands correctly', () {
      expect(formatNumber(1500), '1.5K');
      expect(formatNumber(1000000), '1M');
    });

    test('validateEmail returns true for valid email', () {
      expect(validateEmail('test@example.com'), true);
      expect(validateEmail('invalid'), false);
    });
  });
}
```

**Run tests**
```bash
flutter test
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

### 10.3 Integration Testing

**integration_test/app_test.dart**
```dart
import 'package:flutter_test/flutter_test.dart'
import 'package:integration_test/integration_test.dart'
import 'package:rayzi_app/main.dart' as app

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-end test', () {
    test('login and navigate to home', () async {
      app.main();
      await tester.pumpAndSettle();

      // Enter credentials
      await tester.enterText(find.byType(TextField).first, 'test@example.com');
      await tester.enterText(find.byType(TextField).last, 'password123');

      // Tap login button
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // Verify home screen
      expect(find.byType(BottomNavigationBar), findsOneWidget);
    });
  });
}
```

**Run integration tests**
```bash
flutter test integration_test/app_test.dart
```

### 10.4 Load Testing

**Using Artillery**
```bash
npm install -g artillery
```

**load-test.yml**
```yaml
config:
  target: 'https://your-api.com'
  phases:
    - duration: 60
      arrivalRate: 10
    - duration: 120
      arrivalRate: 50
    - duration: 60
      arrivalRate: 100
  defaults:
    headers:
      Content-Type: 'application/json'

scenarios:
  - name: 'Get live streams'
    weight: 70
    requests:
      - get:
          url: '/api/v1/streams?status=live'

  - name: 'User login'
    weight: 30
    requests:
      - post:
          url: '/api/v1/auth/login'
          json:
            email: 'loadtest@example.com'
            password: 'testpassword'
```

**Run load test**
```bash
artillery run load-test.yml
```

---

## 11. Appendices

### 11.1 SQL Functions Reference

Add these to Supabase SQL Editor after the main migration:

```sql
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

-- Set admin role (run once for your admin user)
-- UPDATE auth.users SET raw_user_meta_data = raw_user_meta_data || '{"role":"admin"}' WHERE email = 'your-admin@email.com';
```

### 11.2 API Endpoint Reference

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/v1/auth/register` | No | Register new user |
| POST | `/api/v1/auth/login` | No | Login user |
| POST | `/api/v1/auth/social` | No | Social login |
| GET | `/api/v1/auth/me` | Yes | Get current user |
| GET | `/api/v1/users/search` | Yes | Search users |
| GET | `/api/v1/users/leaderboard` | Yes | Get leaderboard |
| GET | `/api/v1/users/:id` | Yes | Get user profile |
| PUT | `/api/v1/users/profile` | Yes | Update profile |
| POST | `/api/v1/users/follow` | Yes | Follow user |
| POST | `/api/v1/users/unfollow` | Yes | Unfollow user |
| GET | `/api/v1/users/:id/followers` | Yes | Get followers |
| GET | `/api/v1/users/:id/following` | Yes | Get following |
| GET | `/api/v1/streams` | Yes | List streams |
| POST | `/api/v1/streams` | Yes | Create stream |
| GET | `/api/v1/streams/:id` | Yes | Get stream details |
| GET | `/api/v1/streams/:id/token` | Yes | Get Agora token |
| POST | `/api/v1/streams/:id/join` | Yes | Join stream |
| POST | `/api/v1/streams/:id/leave` | Yes | Leave stream |
| POST | `/api/v1/streams/:id/end` | Yes | End stream (host only) |
| POST | `/api/v1/streams/:id/like` | Yes | Like stream |
| GET | `/api/v1/gifts` | Yes | List gifts |
| POST | `/api/v1/gifts/send` | Yes | Send gift |
| GET | `/api/v1/gifts/transactions` | Yes | Gift history |
| GET | `/api/v1/posts` | Yes | List posts |
| POST | `/api/v1/posts` | Yes | Create post |
| GET | `/api/v1/posts/:id` | Yes | Get post details |
| POST | `/api/v1/posts/:id/like` | Yes | Like post |
| POST | `/api/v1/posts/:id/unlike` | Yes | Unlike post |
| POST | `/api/v1/posts/:id/comment` | Yes | Comment on post |
| DELETE | `/api/v1/posts/:id` | Yes | Delete post |
| GET | `/api/v1/wallet/balance` | Yes | Get wallet balance |
| GET | `/api/v1/wallet/transactions` | Yes | Transaction history |
| POST | `/api/v1/wallet/purchase` | Yes | Purchase coins |
| POST | `/api/v1/wallet/withdraw` | Yes | Request withdrawal |
| GET | `/api/v1/rooms` | Yes | List rooms |
| POST | `/api/v1/rooms` | Yes | Create room |
| POST | `/api/v1/rooms/:id/join` | Yes | Join room |
| POST | `/api/v1/rooms/:id/leave` | Yes | Leave room |
| PUT | `/api/v1/rooms/:id/participants/:uid/role` | Yes | Update participant role |
| GET | `/api/v1/notifications` | Yes | List notifications |
| PUT | `/api/v1/notifications/:id/read` | Yes | Mark as read |
| PUT | `/api/v1/notifications/read-all` | Yes | Mark all read |
| POST | `/api/v1/notifications/push-token` | Yes | Register push token |
| POST | `/api/v1/reports` | Yes | Submit report |
| GET | `/api/v1/admin/dashboard` | Admin | Dashboard stats |
| GET | `/api/v1/admin/users` | Admin | List all users |
| POST | `/api/v1/admin/users/:id/ban` | Admin | Ban user |
| POST | `/api/v1/admin/users/:id/unban` | Admin | Unban user |
| GET | `/api/v1/admin/reports` | Admin | List reports |
| PUT | `/api/v1/admin/reports/:id/resolve` | Admin | Resolve report |
| GET | `/api/v1/admin/streams` | Admin | List all streams |
| POST | `/api/v1/admin/streams/:id/ban` | Admin | Ban stream |
| GET | `/api/v1/admin/gifts` | Admin | List gifts |
| POST | `/api/v1/admin/gifts` | Admin | Create gift |
| PUT | `/api/v1/admin/gifts/:id` | Admin | Update gift |
| GET | `/api/v1/admin/withdrawals` | Admin | List withdrawals |
| PUT | `/api/v1/admin/withdrawals/:id` | Admin | Process withdrawal |

### 11.3 Socket.IO Events

| Event | Direction | Payload | Description |
|-------|-----------|---------|-------------|
| `join-stream` | Client → Server | `streamId: string` | Join stream room |
| `leave-stream` | Client → Server | `streamId: string` | Leave stream room |
| `chat-message` | Client → Server | `{streamId, message}` | Send chat message |
| `send-gift` | Client → Server | `{streamId, giftId, receiverId}` | Send gift |
| `join-room` | Client → Server | `roomId: string` | Join audio room |
| `leave-room` | Client → Server | `roomId: string` | Leave audio room |
| `room-message` | Client → Server | `{roomId, message}` | Send room message |
| `private-message` | Client → Server | `{to, message}` | Send DM |
| `chat-history` | Server → Client | `messages[]` | Recent chat messages |
| `chat-message` | Server → Client | `{userId, username, message, timestamp}` | New chat message |
| `gift-received` | Server → Client | `{senderId, receiverId, gift, timestamp}` | Gift notification |
| `user-joined` | Server → Client | `{userId}` | User joined stream |
| `user-left` | Server → Client | `{userId}` | User left stream |
| `private-message` | Server → Client | `{from, message, timestamp}` | New DM received |

### 11.4 Troubleshooting

**Issue: Agora token generation fails**
- Verify `AGORA_APP_ID` and `AGORA_APP_CERTIFICATE` are correct
- Ensure uid is a 32-bit unsigned integer
- Check token expiration time

**Issue: Supabase RLS blocking queries**
- Verify user is authenticated
- Check RLS policies match your use case
- Use service role key for server-side operations only

**Issue: Socket.IO not connecting**
- Verify CORS settings allow your domain
- Check JWT token is valid and not expired
- Ensure server is running and port is open

**Issue: Flutter build fails**
- Run `flutter clean` and `flutter pub get`
- Verify minSdkVersion >= 21
- Check Android Gradle plugin version compatibility
- Ensure all permissions are in AndroidManifest.xml

**Issue: Push notifications not working**
- Verify Firebase project is configured correctly
- Check `google-services.json` is in `android/app/`
- Ensure device token is registered in database
- Test with Firebase Console directly

**Issue: Docker container crashes**
- Check `.env` file has all required variables
- Verify Redis is running before API starts
- Check logs: `docker-compose logs api`
- Ensure ports are not already in use

### 11.5 Free Tier Limits & Scaling Path

| Service | Free Tier | When to Upgrade |
|---------|-----------|-----------------|
| Supabase | 500MB DB, 1GB storage | > 10K active users |
| Agora | 10,000 mins/mo | > 500 concurrent streams |
| GitHub Actions | 2,000 mins/mo | Large team or frequent builds |
| Firebase | 1M notifications/mo | > 100K users |
| Cloudflare | Unlimited bandwidth | Always free for CDN |

**Upgrade path:**
1. Supabase Pro ($25/mo) — 8GB DB, 100GB storage
2. Agora Pay-as-you-go — $0.99/1000 mins
3. VPS (Hetzner/DigitalOcean) — $5-20/mo for self-hosted API
4. Firebase Blaze plan — pay per use beyond free tier

### 11.6 Security Checklist

- [ ] Change default JWT secret (min 32 chars)
- [ ] Enable RLS on all tables
- [ ] Use service_role key only server-side
- [ ] Store secrets in environment variables, never in code
- [ ] Enable HTTPS only (no HTTP)
- [ ] Set up rate limiting on auth endpoints
- [ ] Validate all user inputs
- [ ] Sanitize chat messages (XSS prevention)
- [ ] Implement content moderation for streams
- [ ] Regular dependency updates
- [ ] Enable 2FA on all service accounts
- [ ] Backup database regularly
- [ ] Monitor for suspicious activity
- [ ] Implement report/ban system (included)
- [ ] Use secure cookie settings
- [ ] Set appropriate CORS origins (not `*` in production)

### 11.7 CLI Agent Instructions

When giving this file to a CLI agent, use this prompt:

```
You are a senior full-stack developer. Execute the complete specification 
in the attached markdown file to build a Rayzi clone live streaming app.

Rules:
1. Follow every code block and command exactly as written
2. Create all files with the exact paths specified
3. Run all setup commands in order
4. If a step fails, stop and report the error
5. Do not skip any sections
6. Ensure all environment variables are properly configured
7. Test each component after implementation

Start with Section 2 (Prerequisites), then proceed sequentially through 
all sections. The complete app includes:
- Supabase database with all tables, RLS, triggers, and functions
- Node.js backend API with all endpoints and Socket.IO
- Flutter mobile app (iOS/Android) with all screens
- Flutter Web admin panel
- Docker deployment setup
- CI/CD pipelines

Report progress after each major section completion.
```

---

## End of Specification

> **Total Sections:** 11  
> **Estimated Implementation Time:** 40-60 hours for experienced developer  
> **Team Size:** 1-2 developers  
> **Maintenance:** Ongoing monitoring, dependency updates, content moderation  

**License:** MIT (for generated code)  
**Last Updated:** 2026-08-21
