# PHM Live — Feature Expansion Spec (v2)
> **Builds on top of:** existing `rayzi-backend` / `rayzi_app` / `rayzi_admin` / Supabase stack (post-remediation, Render-hosted backend, Google Sign-In already integrated)
> **New scope:** Newsfeed (social posts + stories), Top Gifters/Hosts Leaderboard, Badge/Frame Shop (King/Crown/VVIP/VIP), Reseller Recharge System, Host Application System, Profile upgrades (ID copy, level/star/friends, Withdraw, Theme, Entry Animation), decorated usernames, Home feed tabs (All/Video/Audio/Following)
> **Target:** CLI coding agent (Claude Code, Cursor Agent, etc.) working inside the existing repo
> **Status:** Additive migration — do not touch/redo anything already shipped in `003_security_hardening.sql`

---

## Table of Contents
1. [Scope & Assumptions](#1-scope--assumptions)
2. [Architecture Addition](#2-architecture-addition)
3. [Database Migration (004_feature_expansion.sql)](#3-database-migration-004_feature_expansionsql)
4. [Backend API — New Endpoints](#4-backend-api--new-endpoints)
5. [Socket.IO — New Events](#5-socketio--new-events)
6. [Flutter Mobile — New Screens & Widgets](#6-flutter-mobile--new-screens--widgets)
7. [Admin Panel — New Sections](#7-admin-panel--new-sections)
8. [Decorated Username / Name Effects System](#8-decorated-username--name-effects-system)
9. [Random PK Battle with Dual Dragon Effect](#9-random-pk-battle-with-dual-dragon-effect)
10. [High-Quality Camera with 10 Filters](#10-high-quality-camera-with-10-filters)
11. [Inbox: 1-Minute Reels, Photos, Audio/Video Calls](#11-inbox-1-minute-reels-photos-audiovideo-calls)
12. [Rollout Plan (Phases)](#12-rollout-plan-phases)
13. [CLI Agent Instructions](#13-cli-agent-instructions)
14. [Master Checklist — All Features](#14-master-checklist--all-features)

---

## 1. Scope & Assumptions

Reference screenshots show a Bigo-style app ("GoLive") with these modules not yet in PHM Live:

| # | Feature | Screens observed |
|---|---|---|
| 1 | Newsfeed (posts + stories + timeline) | Newsfeed tab, All/Timeline toggle |
| 2 | Top Gifters / Top Hosts leaderboard (+ "Rewardable" variants) | Profile → leaderboard modal |
| 3 | Badge/Frame shop: KING, CROWN, VVIP, VIP tiers | Profile menu → shop rows |
| 4 | Recharge from Reseller | Profile menu |
| 5 | Host Request (apply to become an official host) | Profile menu |
| 6 | Profile upgrades: ID + copy button, diamonds/star/level, Friends/Followers/Following, Withdraw, Theme, Entry Animation | Profile main screen |
| 7 | Decorated/rich-text usernames with crowns, badges, agency tags | Audio room list, live grid |
| 8 | Home discovery feed tabs: All / Video / Audio / Following, with viewer counts and decorative avatar frames | Go Live home screen |

**Assumptions:**
- Existing tables from the original spec (`profiles`, `streams`, `gift_transactions`, `agencies`, `follows`, `rooms`, etc.) stay as-is.
- Backend now runs on Render — all new endpoints follow the existing `/api/v1/...` Express router pattern and reuse the existing JWT auth middleware.
- Payment/coin purchase is still gated behind the real payment provider per the audit; the reseller recharge path below is a **manual/agent-approved** alternative, not a bypass of that control.
- "Friends" is distinct from "Followers/Following" → requires a **mutual friend request** system, not just the existing one-way `follows` table.

---

## 2. Architecture Addition

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│   Flutter App   │────▶│  Node.js API (Render) │────▶│   Supabase      │
│  Newsfeed/Shop/ │◄────│  + new /feed /shop    │◄────│  + 004 migration│
│  Leaderboard/   │     │  /leaderboard /reseller│     │  (posts, shop,  │
│  Profile tabs   │     │  /host-application     │     │  inventory, …)  │
└─────────────────┘     └──────────────────────┘     └─────────────────┘
```

No new external services required — everything reuses Supabase Storage (post images), existing wallet tables, and existing admin JWT/role model.

---

## 3. Database Migration (`004_feature_expansion.sql`)

```sql
-- ============================================
-- NEWSFEED: POSTS, STORIES, COMMENTS
-- ============================================

CREATE TABLE public.posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  author_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT DEFAULT '',
  media_url TEXT,
  media_type TEXT CHECK (media_type IN ('image','video',NULL)),
  visibility TEXT DEFAULT 'public' CHECK (visibility IN ('public','followers')),
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  is_pinned BOOLEAN DEFAULT FALSE,
  is_removed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.post_likes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(post_id, user_id)
);

CREATE TABLE public.post_comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.stories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  author_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  media_url TEXT NOT NULL,
  media_type TEXT DEFAULT 'image' CHECK (media_type IN ('image','video')),
  expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '24 hours'),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.story_views (
  story_id UUID REFERENCES public.stories(id) ON DELETE CASCADE,
  viewer_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  viewed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (story_id, viewer_id)
);

-- ============================================
-- FRIENDS (mutual, distinct from one-way follows)
-- ============================================

CREATE TABLE public.friend_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  requester_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  addressee_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(requester_id, addressee_id)
);
-- "Friends" count = accepted requests where the user is either side

-- ============================================
-- SHOP: BADGES / FRAMES / VIP TIERS / THEMES / ENTRY ANIMATIONS
-- ============================================

CREATE TABLE public.shop_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  category TEXT NOT NULL CHECK (category IN ('badge','avatar_frame','vip_tier','theme','entry_animation','name_effect')),
  tier TEXT CHECK (tier IN ('king','crown','vvip','vip',NULL)),
  name TEXT NOT NULL,
  description TEXT,
  preview_url TEXT,
  price_diamonds INTEGER NOT NULL DEFAULT 0,
  duration_days INTEGER, -- NULL = permanent
  is_active BOOLEAN DEFAULT TRUE,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.user_inventory (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  item_id UUID REFERENCES public.shop_items(id) ON DELETE CASCADE,
  is_equipped BOOLEAN DEFAULT FALSE,
  purchased_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE, -- NULL = permanent
  UNIQUE(user_id, item_id)
);

-- profiles gets pointers to *currently equipped* cosmetics for fast reads
ALTER TABLE public.profiles
  ADD COLUMN equipped_frame_id UUID REFERENCES public.shop_items(id),
  ADD COLUMN equipped_badge_id UUID REFERENCES public.shop_items(id),
  ADD COLUMN equipped_theme_id UUID REFERENCES public.shop_items(id),
  ADD COLUMN equipped_entry_animation_id UUID REFERENCES public.shop_items(id),
  ADD COLUMN name_effect JSONB DEFAULT NULL; -- e.g. {"prefix_emojis":["👑"], "color_gradient":["#f5c518","#fff"], "suffix_badge_item_id": "..."}

-- ============================================
-- RESELLER / AGENT RECHARGE SYSTEM
-- ============================================

CREATE TABLE public.reseller_agents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE UNIQUE,
  diamond_credit_balance BIGINT DEFAULT 0, -- diamonds the reseller can distribute
  commission_rate DECIMAL(5,2) DEFAULT 5.00,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.recharge_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  requester_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  reseller_id UUID REFERENCES public.reseller_agents(id),
  diamonds_requested INTEGER NOT NULL CHECK (diamonds_requested > 0),
  payment_proof_url TEXT, -- screenshot of bKash/Nagad/bank transfer etc.
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  processed_by UUID REFERENCES public.profiles(id),
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- HOST APPLICATION SYSTEM
-- ============================================

CREATE TABLE public.host_applications (
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

-- ============================================
-- LEADERBOARD FUNCTIONS (Top / Rewardable Gifters & Hosts)
-- ============================================

-- Top Gifters (extends the get_top_gifters already in original spec) — adds "rewardable" variant
CREATE OR REPLACE FUNCTION public.get_leaderboard(
  p_type TEXT,      -- 'gifters' | 'hosts'
  p_period TEXT,     -- 'daily' | 'weekly' | 'monthly' | 'all'
  p_rewardable BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(user_id UUID, score BIGINT, rank INTEGER) AS $$
BEGIN
  IF p_type = 'gifters' THEN
    RETURN QUERY
    SELECT gt.sender_id, SUM(gt.total_coins)::BIGINT AS score,
           RANK() OVER (ORDER BY SUM(gt.total_coins) DESC)::INTEGER AS rank
    FROM public.gift_transactions gt
    WHERE (p_period = 'all'
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
    WHERE (p_period = 'all'
      OR (p_period = 'daily' AND gt.created_at >= CURRENT_DATE)
      OR (p_period = 'weekly' AND gt.created_at >= CURRENT_DATE - INTERVAL '7 days')
      OR (p_period = 'monthly' AND gt.created_at >= CURRENT_DATE - INTERVAL '30 days'))
      AND (NOT p_rewardable OR gt.receiver_id IN (SELECT id FROM public.profiles WHERE is_verified = TRUE))
    GROUP BY gt.receiver_id
    ORDER BY score DESC
    LIMIT 100;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.get_leaderboard(TEXT,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_leaderboard(TEXT,TEXT,BOOLEAN) TO authenticated;

-- ============================================
-- RLS — enable on every new table, mirror existing conventions
-- ============================================

ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.story_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reseller_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recharge_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.host_applications ENABLE ROW LEVEL SECURITY;

-- Read-public / write-own pattern for posts & stories
CREATE POLICY "posts_read_all" ON public.posts FOR SELECT USING (NOT is_removed);
CREATE POLICY "posts_write_own" ON public.posts FOR INSERT WITH CHECK (auth.uid() = author_id);
CREATE POLICY "posts_update_own" ON public.posts FOR UPDATE USING (auth.uid() = author_id);
CREATE POLICY "posts_delete_own" ON public.posts FOR DELETE USING (auth.uid() = author_id);

CREATE POLICY "shop_items_read_all" ON public.shop_items FOR SELECT USING (is_active = TRUE);
CREATE POLICY "inventory_read_own" ON public.user_inventory FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "recharge_read_own_or_admin" ON public.recharge_requests FOR SELECT
  USING (auth.uid() = requester_id OR public.is_admin());
CREATE POLICY "recharge_insert_own" ON public.recharge_requests FOR INSERT WITH CHECK (auth.uid() = requester_id);
CREATE POLICY "host_app_read_own_or_admin" ON public.host_applications FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
CREATE POLICY "host_app_insert_own" ON public.host_applications FOR INSERT WITH CHECK (auth.uid() = user_id);

-- (repeat analogous own/admin policies for post_likes, post_comments, stories, story_views, friend_requests)
```

> **Note:** this reuses `public.is_admin()` created in `003_security_hardening.sql` — do not redefine it.

---

## 4. Backend API — New Endpoints

All under existing JWT auth middleware; admin-only routes reuse the existing admin role check.

### Newsfeed
| Method | Endpoint | Auth | Description |
|---|---|---|---|
| GET | `/api/v1/feed/posts?scope=all\|timeline` | Yes | Paginated feed; `timeline` = own+following only |
| POST | `/api/v1/feed/posts` | Yes | Create post (whitelisted fields: `content`, `media_url`, `visibility`) |
| DELETE | `/api/v1/feed/posts/:id` | Yes (own or admin) | Remove post |
| POST | `/api/v1/feed/posts/:id/like` | Yes | Toggle like |
| POST | `/api/v1/feed/posts/:id/comment` | Yes | Add comment |
| GET | `/api/v1/feed/stories` | Yes | Active (non-expired) stories, grouped by author |
| POST | `/api/v1/feed/stories` | Yes | Create story |
| POST | `/api/v1/feed/stories/:id/view` | Yes | Mark viewed |

### Leaderboard
| Method | Endpoint | Auth | Description |
|---|---|---|---|
| GET | `/api/v1/leaderboard?type=gifters\|hosts&period=daily\|weekly\|monthly\|all&rewardable=true\|false` | Yes | Calls `get_leaderboard()` RPC, joins profile display data |

### Shop / Inventory
| Method | Endpoint | Auth | Description |
|---|---|---|---|
| GET | `/api/v1/shop/items?category=` | Yes | List active items (badge/frame/vip_tier/theme/entry_animation) |
| POST | `/api/v1/shop/purchase` | Yes | Atomic RPC: deduct diamonds, insert `user_inventory` row (mirrors existing wallet-RPC pattern — no client-side price trust) |
| GET | `/api/v1/inventory` | Yes | List owned items |
| POST | `/api/v1/inventory/:itemId/equip` | Yes | Set as equipped (unequips previous of same category), updates `profiles.equipped_*` |

### Reseller Recharge
| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/api/v1/reseller/recharge-request` | Yes | User submits request + payment proof upload |
| GET | `/api/v1/reseller/my-requests` | Yes | Status history |
| GET | `/api/v1/admin/reseller/requests` | Admin | List pending requests |
| POST | `/api/v1/admin/reseller/requests/:id/approve` | Admin | Approves → atomic RPC credits diamonds to requester, debits reseller's `diamond_credit_balance` |
| POST | `/api/v1/admin/reseller/requests/:id/reject` | Admin | Rejects with reason |

### Host Application
| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/api/v1/host-application` | Yes | Submit application (one pending at a time — enforce in service layer) |
| GET | `/api/v1/host-application/me` | Yes | Current status |
| GET | `/api/v1/admin/host-applications` | Admin | List pending |
| POST | `/api/v1/admin/host-applications/:id/approve` | Admin | Approves → sets `profiles.role = 'host'` or equivalent flag |
| POST | `/api/v1/admin/host-applications/:id/reject` | Admin | Rejects with reason |

### Friends
| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/api/v1/friends/request/:userId` | Yes | Send request |
| POST | `/api/v1/friends/accept/:requestId` | Yes | Accept |
| POST | `/api/v1/friends/reject/:requestId` | Yes | Reject |
| GET | `/api/v1/friends` | Yes | List accepted friends |
| GET | `/api/v1/friends/count/:userId` | Yes | Count only (for profile header) |

### Profile Extras
| Method | Endpoint | Auth | Description |
|---|---|---|---|
| GET | `/api/v1/profile/summary` | Yes | Returns diamonds, stars, level, friends/followers/following counts, equipped cosmetics — one call for the profile header |
| PUT | `/api/v1/profile/theme` | Yes | Set `equipped_theme_id` (must own item) |
| PUT | `/api/v1/profile/entry-animation` | Yes | Set `equipped_entry_animation_id` (must own item) |

**Security notes carried over from the audit (apply to all new endpoints):**
- No endpoint accepts raw `req.body` into a service-role update — whitelist fields explicitly (this was C2 in the audit).
- All diamond/coin-affecting operations (`shop/purchase`, reseller approve/reject) must be atomic DB RPCs with server-side price/amount lookups — never trust a client-sent price or amount (this was C1/C3 in the audit).
- Reseller `diamond_credit_balance` debit and requester credit happen in the **same transaction** as the RPC.

---

## 5. Socket.IO — New Events

| Event | Direction | Payload | Description |
|---|---|---|---|
| `new-post` | Server → Client | `{postId, authorId}` | Push to followers' feed when someone they follow posts |
| `leaderboard-update` | Server → Client | `{type, period}` | Optional: notify clients to refetch leaderboard after a big gift |
| `host-application-status` | Server → Client | `{status}` | Notify user when admin approves/rejects |
| `recharge-status` | Server → Client | `{requestId, status}` | Notify user when reseller recharge is processed |

These are notifications only — no wallet math happens over sockets (keeps the audit's C4 fix intact: gifts/wallet changes stay REST+RPC only).

---

## 6. Flutter Mobile — New Screens & Widgets

### Newsfeed (`lib/features/feed/`)
- `NewsfeedScreen` — top bar (logo, bell, VIP crown icon, POST button), `StoryBar` (circular avatars, "+": add story), `TabBar` (All/Timeline), infinite-scroll `PostCard` list
- `PostCard` — author row, text, optional media, like/comment/share row, comment count
- `CreatePostScreen` — text input + image picker (reuse existing storage upload service)
- `StoryViewerScreen` — full-screen tap-through story viewer with progress bars

### Leaderboard (`lib/features/leaderboard/`)
- `LeaderboardScreen` — modal/bottom-sheet style matching screenshot: 4 tabs (Top Gifters / Rewardable Gifters / Top Hosts / Rewardable Hosts), period selector (daily/weekly/monthly/all)
- `LeaderboardTile` — rank number/medal, decorated avatar frame widget, decorated username, diamond score
- Top-3 podium widget (circular avatar with colored ring + "TOP 1/2/3" ribbon, matches screenshot layout)

### Shop (`lib/features/shop/`)
- `ShopHomeScreen` — rows: KING / CROWN / VVIP / VIP / Recharge from Reseller / Host Request (as seen in Profile menu)
- `ShopTierScreen` — grid of items for a given tier/category with price + "Buy" button
- `PurchaseConfirmDialog` — shows diamond cost, confirms, calls `/shop/purchase`
- `InventoryScreen` — "My Items" with Equip/Unequip toggle per category

### Reseller Recharge (`lib/features/reseller/`)
- `RechargeFromResellerScreen` — amount input, payment proof image upload, submit
- `MyRechargeRequestsScreen` — status list (pending/approved/rejected)

### Host Request (`lib/features/host/`)
- `HostRequestScreen` — form: full name, phone, ID document upload, sample video upload
- `HostApplicationStatusScreen`

### Profile (`lib/features/profile/`) — extend existing `profile_screen.dart`
- Header: avatar (with equipped frame overlay), `ID: 306188` + copy icon (`Clipboard.setData`), diamond/star/level pill row, Friends/Followers/Following stat row (tap → respective list screens)
- Menu additions: Account, Block List, History, **Withdraw** (already exists per audit — link in), **Theme**, **Entry Animation**, KING/CROWN/VVIP/VIP shop links, Recharge from Reseller, Host Request, Share App, Support, Privacy Policy, Terms & Conditions, Sign Out
- `ThemeSelectorScreen` — grid of owned themes, tap to apply (drives app-wide `ThemeData` via a `ThemeProvider`/Bloc)
- `EntryAnimationSelectorScreen` — grid of owned entry animations with preview playback

### Home Discovery Feed — extend existing home/live list screen
- Tab row: **All / Video / Audio / Following** (filter query param on existing `/streams` and new `/rooms` list calls)
- Live card: thumbnail, decorative avatar frame widget (reuse from leaderboard), decorated username, viewer-count pill with icon, live/audio badge icon top-left

### Shared widgets
- `DecoratedAvatar` — renders `equipped_frame_id` art as an overlay ring around the profile photo
- `DecoratedUsername` (see §8) — rich-text rendering of prefix emojis/badges + gradient text + agency tag

---

## 7. Admin Panel — New Sections

- **Shop Management** — CRUD for `shop_items` (name, tier, price, preview image, active toggle)
- **Reseller Management** — create/manage reseller accounts, adjust `diamond_credit_balance`, view/approve/reject `recharge_requests`
- **Host Applications** — review queue with document/video preview, approve/reject with reason
- **Content Moderation** — extend existing reports view to include `posts`/`post_comments`
- **Leaderboard Config** — toggle which users count as "rewardable" (drives `is_verified` flag already in `profiles`)

All new admin routes reuse the existing `is_admin()`-gated pattern from Phase 3 of the audit remediation — no new auth mechanism.

---

## 8. Decorated Username / Name Effects System

The screenshots show usernames like `👑K👤D💞superAdminkholil💞` and `†MKH† এজেন্সি মনির নিখোঁজ` — these are **not free text**, they're a composed render of:

1. Base `display_name` (user-editable, still whitelisted/validated as before)
2. `profiles.name_effect` JSONB — e.g.:
   ```json
   {
     "prefix_emojis": ["👑", "K"],
     "suffix_emojis": ["💞"],
     "gradient_colors": ["#f5c518", "#ffffff"],
     "agency_tag": "এজেন্সি মনির"
   }
   ```
3. Equipped **badge** shop item (small icon rendered before/after name)
4. `is_verified` / admin role → renders a fixed "Admin"/"Official" chip regardless of `name_effect`

`name_effect` is only settable via `/shop/purchase` + `/inventory/:id/equip` for effect-type items — **never freeform client input**, to avoid abuse (impersonating "Admin"/"Official Reseller" text, which the screenshots show as trust signals).

Client renders this with a `RichText`/`Text.rich` widget (`DecoratedUsername`), never string-concatenation into a single editable field.

---

## 9. Random PK Battle with Dual Dragon Effect

> Source request: "Random PK room by room, two rooms will have two dragons." This is the classic Bigo-style PK Battle mechanic where two independently-live hosts are randomly matched into a timed battle, and each side has an animated **dragon** that visually grows/evolves as their side receives more gifts — the dragon acts as a live visual scoreboard.

### 9.1 How it works
1. A live host taps "PK Battle" → enters a **random matchmaking queue** (not a friend-invite — purely random pairing between two currently-live, PK-eligible hosts).
2. Once matched, both hosts' rooms are linked for the battle duration (default 3 or 5 minutes, admin-configurable).
3. Each room shows **both** video feeds split-screen (host A left / host B right — matches the `VS` layout already in your reference screenshots), each side with its **own dragon**.
4. Every gift sent to either host during the battle adds its coin value to that side's score.
5. The dragon has **5 growth stages** (egg → hatchling → juvenile → adult → legendary) — crossing each score threshold triggers a dragon evolution animation on that side.
6. At the timer's end, the side with the higher score wins; loser gets a "defeat" effect, winner gets a "victory" dragon-roar animation; both dragons reset for the next battle.
7. If a host disconnects mid-battle, that side auto-forfeits after a grace period.

### 9.2 Database additions
```sql
CREATE TABLE public.pk_battles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  stream_a_id UUID REFERENCES public.streams(id) ON DELETE CASCADE,
  stream_b_id UUID REFERENCES public.streams(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'active' CHECK (status IN ('active','ended','forfeited')),
  duration_seconds INTEGER DEFAULT 300,
  score_a INTEGER DEFAULT 0,
  score_b INTEGER DEFAULT 0,
  dragon_stage_a INTEGER DEFAULT 0 CHECK (dragon_stage_a BETWEEN 0 AND 4),
  dragon_stage_b INTEGER DEFAULT 0 CHECK (dragon_stage_b BETWEEN 0 AND 4),
  winner_stream_id UUID REFERENCES public.streams(id),
  started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  ended_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE public.pk_matchmaking_queue (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  stream_id UUID REFERENCES public.streams(id) ON DELETE CASCADE UNIQUE,
  queued_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Dragon stage thresholds (admin-configurable, seeded with defaults)
CREATE TABLE public.pk_dragon_stages (
  stage INTEGER PRIMARY KEY,
  label TEXT NOT NULL,          -- 'Egg','Hatchling','Juvenile','Adult','Legendary'
  score_threshold INTEGER NOT NULL,
  animation_url TEXT
);
```

Score updates happen through the **existing atomic gift RPC** — extend it to also increment `pk_battles.score_a/score_b` when the receiving stream is currently in an active battle, in the same transaction as the coin deduction (do not add a second, separate write path — that would reopen the audit's C4 socket-bypass class of bug).

### 9.3 Backend API & Socket events
| Method/Event | Path/Name | Description |
|---|---|---|
| POST | `/api/v1/pk/queue` | Host enters random matchmaking queue |
| DELETE | `/api/v1/pk/queue` | Cancel queueing |
| GET | `/api/v1/pk/battles/:id` | Battle state (scores, dragon stages, time remaining) |
| POST | `/api/v1/admin/pk/dragon-stages` | Admin: configure thresholds/animations |
| Socket `pk-matched` | Server→Client | `{battleId, opponentStreamId}` — fires when matchmaking pairs two hosts |
| Socket `pk-score-update` | Server→Client | `{battleId, scoreA, scoreB, dragonStageA, dragonStageB}` — realtime score/dragon push during battle |
| Socket `pk-ended` | Server→Client | `{battleId, winnerStreamId}` |

### 9.4 Mobile UI
- `PkQueueButton` on the live-host toolbar → "Finding opponent…" loading state
- `PkBattleView` — split-screen video, VS banner, per-side score bar, **animated dragon widget** per side that swaps sprite/Lottie animation on stage change
- `PkResultOverlay` — victory/defeat animation + updated leaderboard prompt

---

## 10. High-Quality Camera with 10 Filters

> Source request: "High quality camera with 10 filters."

### 10.1 Scope
Upgrade the capture pipeline used for **both live streaming and short-video/reel recording** to:
- Request the highest resolution supported by the device (up to 1080p, capped for bandwidth on live streams; up to device max for recorded reels/photos)
- Provide a horizontally-scrollable **filter carousel** of 10 real-time filters applied live in the camera preview (not just post-processing), e.g.: Natural, Beauty Smooth, Warm, Cool, Vintage, B&W, Vivid, Soft Glow, Cinematic, Night-Bright
- Basic **beauty adjustments** (skin smoothing slider, brightness) as a companion to the filter set, matching what competitor apps bundle alongside filters

### 10.2 Technical approach
- Flutter: use the `camera` plugin for capture + a GPU shader/image-processing layer (`GPUImage`-style pipeline or platform-channel to native `CameraX`/`AVFoundation` filter APIs) to apply filters at preview time, so the filter is visible in real time on both the streamer's own preview and (for reels) the recorded output.
- Filters are implemented as reusable **LUT (look-up table) or fragment-shader presets**, stored as static assets — no server round-trip needed to apply a filter.
- Store the user's **last-used filter/beauty settings** per user (small `profiles.camera_prefs JSONB` column or a dedicated `camera_settings` table) so it persists between sessions.

### 10.3 Database addition (optional persistence)
```sql
ALTER TABLE public.profiles
  ADD COLUMN camera_prefs JSONB DEFAULT '{"filter": "natural", "beauty_level": 0, "brightness": 0}'::jsonb;
```

### 10.4 Mobile UI
- `CameraFilterCarousel` — 10 circular filter thumbnails with live preview thumbnails, horizontally scrollable, selected filter highlighted
- `BeautyAdjustPanel` — sliders for smoothing/brightness, collapsible drawer under the carousel
- Applies identically inside: **Go Live setup screen**, **live streaming view (host side)**, and **Reel recording screen** (§11)

---

## 11. Inbox: 1-Minute Reels, Photos, Audio/Video Calls

> Source request: "In the inbox, 1-minute reel videos, photos, and audio/video calls."

### 11.1 Scope
Upgrade the existing Chats/Inbox module (currently just text, per the original spec's `private-message` socket event) into a **rich direct-messaging inbox** supporting:
1. **Reel-style video messages** — record or pick a video, hard-capped at **60 seconds**, sent inline in the conversation, auto-plays muted with tap-to-unmute (like a chat "reel")
2. **Photo messages** — pick/capture and send images inline
3. **In-chat audio and video calls** — start a 1-to-1 audio or video call directly from a conversation thread (reuses the existing Agora-based 1-to-1 Video Call feature from the base spec, but now callable straight from Inbox rather than only from a separate "Random/1-to-1 Call" tab)

### 11.2 Database additions
```sql
CREATE TABLE public.conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_a_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_b_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_message_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_a_id, user_b_id)
);

CREATE TABLE public.messages (
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

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "conversations_own" ON public.conversations FOR SELECT
  USING (auth.uid() IN (user_a_id, user_b_id));
CREATE POLICY "messages_own_conversation" ON public.messages FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.conversations c WHERE c.id = conversation_id AND auth.uid() IN (c.user_a_id, c.user_b_id)));
CREATE POLICY "messages_insert_own" ON public.messages FOR INSERT
  WITH CHECK (auth.uid() = sender_id);
```
The 60-second cap on `video_reel` messages is enforced **both** client-side (recording UI hard-stops at 60s) **and** server-side (the CHECK constraint above rejects anything longer if a client is bypassed).

### 11.3 Backend API & Socket events
| Method/Event | Path/Name | Description |
|---|---|---|
| GET | `/api/v1/inbox/conversations` | List conversations, sorted by `last_message_at` |
| GET | `/api/v1/inbox/conversations/:id/messages` | Paginated message history |
| POST | `/api/v1/inbox/conversations/:id/messages` | Send text/photo/video_reel message (media pre-uploaded to Supabase Storage, URL passed in) |
| POST | `/api/v1/inbox/conversations/:id/call` | Log a call attempt, returns Agora token (reuses existing token service) |
| PUT | `/api/v1/inbox/conversations/:id/read` | Mark read |
| Socket `inbox-message` | Server→Client | New message push |
| Socket `inbox-call-incoming` | Server→Client | `{conversationId, callerId, callType}` — incoming call ring |
| Socket `inbox-call-ended` | Server→Client | `{conversationId, durationSeconds}` — logs `call_log` message on end |

### 11.4 Mobile UI
- `InboxListScreen` — conversation list with last message preview, unread badge
- `ConversationScreen` — message bubbles for text/photo/video-reel; tap a video-reel bubble to play inline; call icons (audio + video) in the app bar
- `ReelRecorderSheet` — reuses the Camera + Filter module from §10, hard 60-second countdown ring during recording
- `InCallScreen` — reuses existing 1-to-1 video/audio call UI from the base spec, entered via the Inbox call icons

---

## 12. Rollout Plan (Phases)

### Phase A — Data & Read-only features (2–3 days)
- [ ] Run `004_feature_expansion.sql` (after review) in Supabase
- [ ] Seed initial `shop_items` (King/Crown/VVIP/VIP tiers, a few frames/themes/entry animations)
- [ ] Backend: leaderboard endpoint + admin shop CRUD
- [ ] Mobile: Leaderboard screen, Shop browse screens (no purchase yet)

### Phase B — Economy-safe purchase & inventory (2–3 days)
- [ ] `shop/purchase` atomic RPC (mirrors existing wallet RPC pattern — server-side price lookup, DB transaction)
- [ ] Inventory + equip endpoints; `DecoratedAvatar`/`DecoratedUsername` widgets wired everywhere usernames render

### Phase C — Newsfeed (3–4 days)
- [ ] Posts/stories tables, endpoints, moderation hooks into existing reports system
- [ ] Mobile Newsfeed + Story bar + Create Post

### Phase D — Reseller & Host systems (2–3 days)
- [ ] Reseller tables/endpoints + admin approval queue
- [ ] Host application flow + admin review queue
- [ ] Notifications via existing push/notification service

### Phase E — Home feed tabs, Friends, Theme/Entry Animation (2 days)
- [ ] All/Video/Audio/Following filters on discovery feed
- [ ] Friend request system + counts on profile
- [ ] Theme provider wiring + entry animation playback on stream/room join

### Phase F — Random PK Battle + Dual Dragon (3–4 days)
- [ ] `pk_battles`, `pk_matchmaking_queue`, `pk_dragon_stages` tables + RLS
- [ ] Random matchmaking service (queue → pair → link two streams)
- [ ] Gift RPC extended to update PK score atomically in the same transaction
- [ ] Realtime score/dragon-stage push via sockets
- [ ] Mobile: split-screen PK view, dragon animation widget, result overlay

### Phase G — Camera Upgrade: High-Quality + 10 Filters (2–3 days)
- [ ] Upgrade capture resolution settings (live + reel recording)
- [ ] Build/license 10 real-time filter presets (LUT or shader-based)
- [ ] `CameraFilterCarousel` + `BeautyAdjustPanel` widgets
- [ ] Wire into Go Live setup, live host view, and Reel recorder
- [ ] Persist last-used filter/beauty settings per user

### Phase H — Inbox Upgrade: Reels, Photos, Calls (2–3 days)
- [ ] `conversations` / `messages` tables + RLS + 60-second server-side CHECK
- [ ] Inbox REST endpoints + media upload flow (reuse Supabase Storage)
- [ ] In-chat call initiation (reuse existing Agora token service)
- [ ] Mobile: rich `ConversationScreen`, `ReelRecorderSheet` (uses Phase G camera module), in-call UI reuse

### Exit criteria
`004 migration applied ✓ · all new RLS policies verified with a non-admin test user ✓ · shop purchase cannot be spoofed (price/amount server-side only) ✓ · reseller/host approval flows require admin role ✓ · decorated usernames cannot be set to impersonate Admin/Official without an actual equipped item ✓ · PK score updates only happen through the atomic gift RPC, never a separate write path ✓ · video-reel messages cannot exceed 60s even if the client is bypassed (server CHECK constraint) ✓ · flutter analyze 0 issues on new code ✓`

---

## 13. CLI Agent Instructions

```
You are a senior full-stack developer working inside the existing PHM Live
(rayzi-clone) repository, now deployed with backend on Render and Google
Sign-In already integrated.

Rules:
1. Do NOT modify or re-run 001/002/003 migrations — this is additive.
2. Follow §3 exactly for schema; adjust only if a referenced table/column
   name differs from what's actually in the current repo (inspect first).
3. Every diamond/coin-affecting endpoint MUST be an atomic server-side RPC —
   never trust client-sent prices or amounts (see audit findings C1/C3).
4. Every new table needs RLS enabled + policies before merging (see audit
   finding: DB previously had RLS gaps).
5. Reuse the existing is_admin() helper and JWT auth middleware — do not
   invent a second auth mechanism.
6. Build in the phase order in §12 (Phases A through H). Report progress
   and run `flutter analyze` / `npm run lint` / `npm run build` after each
   phase.
7. If a step conflicts with existing code, stop and report rather than
   guessing.

Start with Phase A.
```

---

## 14. Master Checklist — All Features

Use this as the single source of truth to track delivery. Group by module; check off as each lands in a build that passes `flutter analyze` / `npm run lint` / `npm run build`.

### Newsfeed
- [ ] `posts`, `post_likes`, `post_comments`, `stories`, `story_views` tables + RLS
- [ ] Feed endpoints (list/create/delete/like/comment)
- [ ] Story create/list/view endpoints
- [ ] `NewsfeedScreen` with All/Timeline tabs
- [ ] `StoryBar` + `StoryViewerScreen`
- [ ] `CreatePostScreen`
- [ ] Post moderation hooked into existing reports/admin system

### Leaderboard
- [ ] `get_leaderboard()` RPC (gifters/hosts × daily/weekly/monthly/all × rewardable)
- [ ] `/api/v1/leaderboard` endpoint
- [ ] `LeaderboardScreen` with 4 tabs + period selector
- [ ] Top-3 podium widget + ranked list tiles

### Shop & Inventory
- [ ] `shop_items`, `user_inventory` tables + RLS
- [ ] `profiles.equipped_*` columns
- [ ] Atomic `shop/purchase` RPC (server-side price only)
- [ ] `/api/v1/shop/items`, `/api/v1/inventory`, `/api/v1/inventory/:id/equip`
- [ ] `ShopHomeScreen` (King/Crown/VVIP/VIP rows)
- [ ] `ShopTierScreen`, `PurchaseConfirmDialog`, `InventoryScreen`
- [ ] Admin Shop Management CRUD

### Reseller Recharge
- [ ] `reseller_agents`, `recharge_requests` tables + RLS
- [ ] Request/approve/reject endpoints (atomic credit/debit RPC)
- [ ] `RechargeFromResellerScreen`, `MyRechargeRequestsScreen`
- [ ] Admin reseller approval queue

### Host Application
- [ ] `host_applications` table + RLS
- [ ] Apply/status/admin-review endpoints
- [ ] `HostRequestScreen`, `HostApplicationStatusScreen`
- [ ] Admin host-application review queue

### Profile Upgrades
- [ ] `/api/v1/profile/summary` endpoint
- [ ] ID + copy-to-clipboard on profile header
- [ ] Diamonds/Star/Level pill row
- [ ] Friends/Followers/Following counters (+ `friend_requests` table + endpoints)
- [ ] Withdraw, Theme, Entry Animation menu items wired
- [ ] `ThemeSelectorScreen`, `EntryAnimationSelectorScreen`

### Decorated Usernames
- [ ] `profiles.name_effect` JSONB column
- [ ] `DecoratedUsername` rich-text widget (no freeform impersonation of Admin/Official)
- [ ] `DecoratedAvatar` frame-overlay widget
- [ ] Applied everywhere usernames render (feed, leaderboard, live grid, audio rooms, inbox)

### Home Discovery Feed
- [ ] All / Video / Audio / Following tabs on home/live grid
- [ ] Viewer-count pill + live/audio badge on cards
- [ ] Decorative avatar frame on live cards

### Random PK Battle + Dual Dragon
- [ ] `pk_battles`, `pk_matchmaking_queue`, `pk_dragon_stages` tables + RLS
- [ ] Random matchmaking (room-to-room, not friend-invite)
- [ ] Gift RPC extended to update PK score atomically
- [ ] Dragon 5-stage growth logic + admin-configurable thresholds
- [ ] Realtime score/dragon push via sockets
- [ ] `PkQueueButton`, `PkBattleView` (split-screen + dragons), `PkResultOverlay`

### High-Quality Camera + 10 Filters
- [ ] Capture resolution upgrade (live stream + reel recording)
- [ ] 10 real-time filter presets (LUT/shader-based)
- [ ] `CameraFilterCarousel` + `BeautyAdjustPanel`
- [ ] Wired into Go Live setup, live host view, Reel recorder
- [ ] Persisted per-user camera preferences

### Inbox: Reels, Photos, Calls
- [ ] `conversations`, `messages` tables + RLS + 60s server-side CHECK on reels
- [ ] Inbox list/message/call endpoints
- [ ] `InboxListScreen`, `ConversationScreen`
- [ ] `ReelRecorderSheet` (60s hard cap, reuses camera/filter module)
- [ ] In-chat audio/video call initiation reusing existing Agora call flow

### Security & Ops (cross-cutting — verify at the end of every phase)
- [ ] No client-sent price/amount trusted anywhere new (mirrors audit C1/C3)
- [ ] No raw `req.body` mass-assigned into any table (mirrors audit C2)
- [ ] Every new table has RLS enabled with tested policies
- [ ] Every new admin route requires `is_admin()`
- [ ] `flutter analyze` clean on both `rayzi_app` and `rayzi_admin`
- [ ] `npm run lint` / `npm run build` clean on backend
- [ ] CI green on main after each phase merge

---

## End of Spec

**Depends on:** original `rayzi_clone_cli_spec.md` + `AUDIT-PLAN.md` remediation (Phases 0–4)
**Estimated time:** 18–24 days for 1 developer across Phases A–H
**Last updated:** 2026-08-23
