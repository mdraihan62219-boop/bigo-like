# PHM Live — Full Project Audit #2 (Post-Expansion)

**Date:** 2026-08-23 · **Scope:** entire workspace after the 8-phase v2 feature expansion (Newsfeed, Leaderboard, Shop, Reseller, Host Application, Profile upgrades, PK Dragon, Camera Filters, Inbox), Render backend deployment, Google Sign-In integration, and Reels feature.
**Method:** static review of all new/changed code + **live execution probes** against `https://bigo-like-1.onrender.com` and the production Supabase project (`yuokeoduqtxgfdlwuaaw`) — auth rejection matrix, Agora token generation, RLS enforcement tests, migration-state introspection, economy-gate checks.

> **Investigation only — no code modified in this pass** (except throwaway probe
> scripts under `rayzi-backend/scripts/_*.mjs`, deleted after use).

---

## 1. Executive Summary

> ## ⚠️ SAFE TO CONTINUE TESTING — but 4 operator actions block headline features.
>
> The platform is structurally healthy: all v2 endpoints are live and authenticated correctly,
> the full live integration suite passes **43/43**, migrations are applied, RLS demonstrably
> blocks anonymous writes on every probed table, and the original audit's economy fixes held
> (purchase gate 501 ✓, mass-assignment whitelist ✓, admin plane 403 ✓).
> A **critical session-leakage bug was found and already fixed during testing** (see F-01 —
> it shipped and was patched within this audit cycle; listed for the record).
>
> **Blocked until real credentials exist (all operator-side, not code):**
> 1. 🔴 Live streaming / calls — placeholder Agora credentials both sides → `AgoraRtcException(-101)`
> 2. 🔴 Google Sign-In — no client ID in build + Supabase provider disabled (live-confirmed)
> 3. 🟠 Avatar/thumbnail uploads — 4 of 5 required storage buckets do not exist
> 4. 🟠 Push notifications — Firebase never configured (dead path)

**Component verdicts**

| Component | Builds | Checks | Production-safe | Verdict |
|---|---|---|---|---|
| rayzi-backend | ✅ tsc clean | ✅ lint 0 · tests 6/6 · live suite 43/43 | ✅ once Agora/Google creds set | **OK*** |
| rayzi_app | ✅ analyze 0 err/warn | ✅ tests 7/7 · release APK builds | ❌ streaming & Google sign-in dead without creds | **CONDITIONAL** |
| rayzi_admin | ✅ web/index.html present | ✅ analyze clean (7 pre-existing infos) | ✅ role-gated via backend | **OK** |
| supabase | 005 applied ✓ | tables/columns/RLS verified live | ⚠️ missing buckets; Google provider off | **CONDITIONAL** |
| infra/CI | lockfiles committed | CI green-capable | ⚠️ no dart-defines in APK job | **CONDITIONAL** |

---

## 2. Root Causes of the Three Observed Symptoms *(priority section)*

### Symptom A — 401 errors on Audio Rooms list, Notifications, Go-Live create
**Verdict: server is CORRECT; the client had no valid token. Reproduced and classified live:**

| Probe (live) | Status | Exact server reason | Meaning |
|---|---|---|---|
| `GET /rooms` — no header | 401 | `"No token provided"` (`auth.ts:17`) | Guest mode or token store empty |
| `GET /rooms` — garbage JWT | 401 | `"Authentication failed"` (`auth.ts:37–38` catch) | jwt.verify threw (malformed) |
| `GET /rooms` — valid-format JWT signed with wrong secret | 401 | `"Authentication failed"` | **Signature mismatch** → stale token after any `JWT_SECRET` change on Render |
| Same three probes on `/notifications` + `POST /streams` | 401 | identical messages | same two causes |
| All three endpoints with a freshly issued token | **200** | success | server-side auth fully functional |

Root cause chain: user was either browsing as guest ("Skip for now") or holding a token signed with a previous `JWT_SECRET`. Client behaviour verified: `api_service.dart:22–28` clears the stored token on any 401 (correct), and screens surface SnackBars instead of crashing — but the user stays on the screen seeing raw Dio error text until app restart (see F-08).

### Symptom B — `AgoraRtcException(-101)` on stream join and Go-Live
**Verdict: invalid Agora App ID — placeholders everywhere. Chain reproduced end-to-end:**
1. `rayzi_app/lib/config/constants.dart:20` → `agoraAppId = 'your-agora-app-id'` → engine initialized with an invalid App ID → Agora SDK throws **-101 `INVALID_APP_ID`** before any network call.
2. Backend `rayzi-backend/.env`: `AGORA_APP_ID` / `AGORA_APP_CERTIFICATE` are placeholder strings (verified by pattern check — values redacted).
3. With placeholders, `agora-token@2.x`'s `RtcTokenBuilder.buildTokenWithUid(...)` **silently returns `""`** (reproduced locally) → live probe `GET /api/v1/streams/:id/token` returned `200 {"token":"", ...}`.
4. Joining with empty token + invalid App ID = guaranteed -101 regardless of token logic.

Not a certificate mismatch, not a token-generation bug — pure configuration. Single fix point: set real credentials in Render env **and** replace `constants.dart:20` (or add an `AGORA_APP_ID` dart-define).

### Symptom C — "Google sign-in is not configured" message
**Verdict: two independent missing pieces, both confirmed:**
1. **Client ID absent from build:** `GOOGLE_WEB_CLIENT_ID` defaults to `''` (`constants.dart:22–29`); `.github/workflows/flutter.yml:64,67,103` runs bare `flutter build apk --release` / `appbundle` / `ios` with **no `--dart-define`s at all**. `GoogleAuthService.getIdToken()` therefore throws `GoogleAuthConfigurationException` (by design).
2. **Supabase provider disabled:** live probe `POST /api/v1/auth/social {"provider":"google","token":"fake"}` → Supabase replies `"Provider (issuer \"https://accounts.google.com\") is not enabled"`. Even with a correct client ID compiled in, the backend step would fail until Google OAuth is enabled in the Supabase dashboard with matching Web/Audio client IDs.

---

## 3. Findings

Legend: 🔴 CRITICAL · 🟠 HIGH · 🟡 MEDIUM · ⚪ LOW. `[LIVE]` = reproduced by execution during this audit.

| ID | Sev | Area | File(s) | Description | Suggested fix |
|---|---|---|---|---|---|
| F-01 | 🔴→✅ FIXED | backend/auth | `src/config/database.ts`, `src/controllers/auth.controller.ts` | Login/register/social ran on the **shared service-role client**; supabase-js stores that session and re-scoped every subsequent request as *whoever logged in last* (cross-user contamination + non-bypassing RLS). Surfaced as conversations RLS failures; found by differential repro (local service call OK, Render failed). | Already fixed this cycle (`88e6a88`): per-call `createAuthClient()` for all `supabase.auth.*`; shared client data-only. Keep rule documented. |
| F-02 | 🔴 | config/agora | `rayzi_app/lib/config/constants.dart:20`, `rayzi-backend/.env` | Placeholder AGORA_APP_ID/CERTIFICATE on both sides → -101 on every join; backend issues empty tokens silently. [LIVE] | Set real values in Render env + Flutter constants/dart-define; fail fast at boot if `AGORA_APP_CERTIFICATE` looks like a placeholder. |
| F-03 | 🔴 | config/google | `rayzi_app/lib/config/constants.dart:22–29`, `.github/workflows/flutter.yml:64–103` | `GOOGLE_WEB_CLIENT_ID` never passed to any build (no dart-defines anywhere in CI); Supabase Google provider disabled. [LIVE: "Provider … not enabled"] | Add dart-define to CI + local build script; enable Google provider in Supabase Auth with matching Web/Android OAuth clients (SHA-1 registered). |
| F-04 | 🟠 | supabase/storage | live project | Only `post-media` bucket exists. `avatars`, `stream-thumbnails`, `gift-animations`, `room-covers` missing → avatar edit, stream thumbnails, gift animations will 404 on upload/display. [LIVE: listBuckets] | Create the four public buckets (one SQL/API call or dashboard click each). |
| F-05 | 🟠 | backend/config | Render env (inferred), `.env.example` | `CORS_ORIGIN` unset → allowlist falls back to localhost origins (`cors.ts:12–17`). Native Flutter unaffected; **admin web panel hosted on any other domain will be CORS-blocked**. `NODE_ENV=development` also leaks into `/health` output. | Set `CORS_ORIGIN=https://<admin-domain>` and `NODE_ENV=production` in Render env. |
| F-06 | 🟠 | push/firebase | `rayzi-backend/src/config/firebase.ts`, `rayzi_app/android/app/google-services.json` (placeholder, gitignored) | Push notifications dead end-to-end: Firebase env vars absent ([LIVE] boot warning), real `google-services.json` never provided. | Provide real Firebase project file + service-account env vars when push is needed. |
| F-07 | 🟡 | backend/agora | `src/services/agora.service.ts`, inbox/pk/stream controllers | Token drift: none — stream/PK/inbox calls share one `AgoraService.generateToken` ✓. But callers can't distinguish "unconfigured" from "valid": inbox call returns `success:true` with `token:""` [LIVE]. | Add startup credential validation; return 503 `Agora not configured` from token endpoints when placeholder detected. |
| F-08 | 🟡 | mobile/ux | `lib/services/api_service.dart:22–28`, tab screens | 401 handler clears token but doesn't navigate to login; user remains on screen with raw `DioException` text in SnackBars until restart. Guest mode itself works (splash → home, no stale token sent). | Global 401 → broadcast logout event / redirect to login route. |
| F-09 | 🟡 | mobile/spec-gap | `lib/features/pk/pk_screens.dart:23–27` | PK battle view polls REST every 3 s; `pk-score-update` socket events are emitted by backend but never subscribed client-side (spec §9.3 realtime intent). | Subscribe via SocketService in PkBattleView; keep polling as fallback only. |
| F-10 | 🟡 | ops/test | `rayzi-backend/scripts/test-live.mjs` | Live smoke test creates throwaway auth users in the **production** Supabase project (junk accumulates; email rate-limit risk if register path used). | Periodically purge `phm.live.*` users, or point test runs at a staging project. |
| F-11 | ⚪ | mobile/dead-code | `lib/presentation/screens/messages_tab.dart` | Still exported in `screens.dart` but unused since Inbox replaced it in home nav. | Delete file + export. |
| F-12 | ⚪ | infra | `nginx/nginx.conf:16,24` | `api.yourdomain.com` placeholders remain (unchanged from audit #1; irrelevant while on Render direct URL). | Fill in when custom domain lands. |
| F-13 | ⚪ | backend/misc | `src/middleware/rateLimiter.ts` | Redis absent → per-instance in-memory limiter (fine single-instance on Render free tier; becomes a gap if scaled horizontally). | Configure Upstash/Redis when scaling. |

### Verified-good (evidence, this pass)
- **Migration state matches repo [LIVE]:** all expansion tables exist (`stories, story_views, friend_requests, shop_items, user_inventory, reseller_agents, recharge_requests, host_applications, pk_matchmaking_queue, pk_dragon_stages(5 stages seeded), conversations, messages`); v2 columns present (`profiles.equipped_*/name_effect/camera_prefs`, `posts.visibility/is_removed`, `pk_battles.dragon_stage_*/duration_seconds`).
- **RLS enforced [LIVE]:** anon INSERT denied on `posts/stories/shop_items/conversations/recharge_requests` (42501); anon PATCH on a real profile row did **not** land (204s elsewhere were zero-row-match artifacts — methodology corrected mid-audit).
- **Economy gates intact [LIVE]:** `POST /wallet/purchase` → 501 gate; `PUT /users/profile {coins:999999}` → coins stayed 0 (whitelist works); `/admin/stats` as normal user → 403.
- **New money paths reviewed statically:** purchase/equip = server-side price lookup + wallet RPCs + compensating refund (same pattern as GiftService); reseller approve = single RPC with `FOR UPDATE` row locks; PK scoring rides the gift write path only (no second write path) — no C1/C3/C4-class regression found.
- **Auth middleware coverage:** every Phase A–H router mounts `authenticate` (grep-verified list in appendix); admin additions sit behind `authenticate + requireAdmin`.
- **Reproducibility:** `package-lock.json` + both `pubspec.lock`s committed; `.env*` properly gitignored; admin `web/index.html` present.
- **Regression [LIVE]:** legacy `GET /posts?media_type=video` guest-safe ✓; `GET /streams?following=true` ✓; profile summary returns legacy fields (coins/level/followers) alongside new ones — no old-column breakage.

---

## 4. Outstanding Items from Original Audit — Carried Forward

| Original item | Status |
|---|---|
| Run `003_security_hardening.sql` | ✅ Done (is_admin active — admin routes enforce it live) |
| Storage buckets per README | ⚠️ Partial — `post-media` exists; **4 buckets still missing** (F-04) |
| Promote admin user (`profiles.role='admin'`) | ❓ Unknown — cannot verify without operator's account; endpoint enforcement works either way |
| Real `google-services.json` | ❌ Open (F-06) — placeholder only, gitignored, CI self-skips |
| `CORS_ORIGIN`, rate-limit envs in production | ❌ Open (F-05) — fallbacks active |
| nginx TLS/domain | ❌ Open (F-12) — deferred until custom domain |
| Stripe/Razorpay then re-enable purchases | ❌ Open by design — 501 gate holds [LIVE] |
| ~~ESLint config~~ · ~~11 analyzer errors~~ · ~~admin web build~~ · ~~vacuous tests~~ | ✅ Stay fixed (re-verified this pass: lint 0, analyze 0 err/warn ×2 apps, tests 6/6 + 7/7) |

---

## 5. Recommended Fix Order (for the follow-up prompt)

1. **Operator (no code):** Agora credentials (Render env + constants) → unblocks -101 instantly; create 4 storage buckets; enable Google provider in Supabase dashboard; obtain Google Web OAuth client ID.
2. **Code:** wire dart-defines into CI/local build script (`GOOGLE_WEB_CLIENT_ID`, optionally `API_BASE_URL`); boot-time placeholder detection for Agora/Firebase (fail-fast warnings); global 401 → login redirect; PK socket subscription; delete `messages_tab.dart`.
3. **Ops hygiene:** set `NODE_ENV=production` + `CORS_ORIGIN` on Render; schedule cleanup of smoke-test users.

---

## 6. Audit Trail

- Env matrix: `process.env` grep (17 vars) cross-checked against local `.env` via boolean placeholder scanner (values never printed); Render env inferred through behavioural probes.
- Auth matrix: 10 live probes across rooms/notifications/go-live × {none, garbage, wrong-secret, valid} tokens (§2-A table).
- Agora: dependency-level reproduction of silent-empty-token behaviour + live token-endpoint capture.
- DB: 16 REST introspection probes (tables/columns) + 8 RLS enforcement probes incl. controlled marker-write with restore.
- Economy/admin gates: 4 live probes. Regression: full `test-live.mjs` suite 43/43 post-fix.
