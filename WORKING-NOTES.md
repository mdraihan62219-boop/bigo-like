# PHM Live Feature Expansion — Working Notes

Source spec: `phm_live_feature_expansion_spec.md` (v2). Followed §12 phase order.

## Status: ALL PHASES COMPLETE ✅

## Repo facts (verified)
- `posts/post_likes/post_comments` already existed (001) → migration ALTERs posts
  (`visibility`, `is_removed`); feed reuses existing column names (`user_id`, `media_urls`).
- Migration number: `005_feature_expansion.sql` (004 = seed_example_reels).
- `pk_battles` existed (001, stream_id_1/2) → migration adds dragon stages + forfeited status.
- profiles already had coins/diamonds/level/follower_count/following_count.
- No Postgres URL in env → DDL ships as SQL file; user runs 005 in Supabase SQL Editor,
  then `node scripts/seed-shop.mjs`. Reels seed (`seed-reels.mjs`) works without it.

## Delivered by phase
- A: 005 migration (idempotent), shop seed script, GET /leaderboard endpoint, admin shop CRUD,
    mobile LeaderboardScreen v2 (4 tabs × period × podium), ShopHome/ShopTier screens.
- B: atomic purchase_shop_item + equip_inventory_item RPCs; /shop /inventory endpoints;
    InventoryScreen; DecoratedAvatar/DecoratedUsername shared widgets.
- C: /feed endpoints (+ new-post socket); NewsfeedScreen (All/Timeline), StoryBar,
    StoryViewerScreen, CreatePostScreen, CreateStoryScreen.
- D: reseller request/approve(RPC)/reject + agents; host applications + role promotion;
    mobile RechargeFromReseller/MyRechargeRequests/HostRequest screens.
- E: home discovery tabs (All/Video/Audio/Following incl. backend following filter);
    friend_requests system + endpoints; profile summary endpoint (ID/diamonds/level/
    friends row in ProfileTab); ThemeSelector + EntryAnimationSelector screens.
- F: PK matchmaking queue + battle state/end endpoints; pk_apply_score RPC wired into the
    single gift write path; pk-matched/pk-score-update sockets; PkQueueButton + PkBattleView
    (split-screen VS + 5-stage dragon).
- G: 10 ColorFilter matrix presets (live-applicable), CameraFilterCarousel + beauty sliders,
    FilteredPreview widget, per-user camera_prefs persistence endpoint.
- H: conversations/messages tables (60s reel CHECK) + inbox REST; InboxListScreen +
    ConversationScreen (text/photo/reel bubbles, call buttons via Agora token endpoint),
    inbox-message/inbox-call-incoming/inbox-call-ended sockets.

## Verification
- backend: npm run lint ✓ npm run build ✓ npm test 6/6 ✓
- rayzi_app: flutter analyze 0 errors/warnings ✓ flutter test 7/7 ✓ release APK built ✓
- rayzi_admin: flutter analyze clean of new issues ✓

## ONE MANUAL STEP for the user
1. Supabase SQL Editor → run `supabase/migrations/005_feature_expansion.sql`
2. `cd rayzi-backend && node scripts/seed-shop.mjs`
3. Push this branch → Render auto-deploys backend with all new endpoints.
