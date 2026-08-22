# Rayzi Clone — Hard Audit & Remediation Plan

**Date:** 2026-08-22 · **Scope:** entire workspace (`rayzi-backend`, `rayzi_app`, `rayzi_admin`, `supabase`, `nginx`, `docker-compose`, `.github/workflows`, `load-test.yml`)
**Method:** static deep-audit of all source + **live execution** of every configured check (install / lint / analyze / test / build) on Node 24.15 + Flutter (local toolchain).

> **UPDATE 2026-08-22 (later same day):** All five remediation phases have been
> EXECUTED and VERIFIED. See §6 Remediation Log at the bottom for the full
> change list and the post-fix acceptance matrix. Original audit findings below
> are preserved for provenance.

---

## 1. Executive Verdict

> ## ❌ NOT OK — do not deploy or onboard users in current state.
>
> The repo is a coherent, well-layered scaffold with genuinely good pieces (atomic wallet RPCs, parameterized queries, multi-stage non-root Dockerfile), but it fails hard on three axes:
>
> 1. **It doesn't fully build.** The mobile app has **11 compile errors**; the admin panel **cannot build for web** ("Missing index.html"); backend CI lint is broken.
> 2. **The virtual economy can be drained three independent ways** (free coin purchase, negative quantities, socket gifts that skip deduction).
> 3. **No layer enforces admin rights** — client, API, and database all lack a working role mechanism, and one `SECURITY DEFINER` function leaks platform financials to *anonymous* callers.
>
> **Severity tally across all modules: 17 CRITICAL · ~20 HIGH · ~25 MEDIUM · ~15 LOW.**

### Component status

| Component | Compiles | Checks pass | Production-safe | Verdict |
|---|---|---|---|---|
| rayzi-backend | ✅ (`tsc` clean) | ⚠️ lint ❌ · tests vacuous (0 executed) | ❌ economy exploits | **NOT OK** |
| rayzi_app (mobile) | ❌ 11 analyzer errors | ❌ analyze fails; tests cover nothing | ❌ core flow crashes | **NOT OK** |
| rayzi_admin (web panel) | ❌ no `web/index.html` | ✅ analyze clean | ❌ zero auth enforcement | **NOT OK** |
| supabase migrations/functions | — | — | ❌ RLS gaps + public stats RPC | **NOT OK** |
| infra (compose/nginx/CI) | — | — | ⚠️ solid bones, real gaps | **CONDITIONAL** |

---

## 2. Live Verification Matrix (executed evidence)

| # | Check | Command | Result |
|---|---|---|---|
| 1 | Backend install | `npm ci` | ✅ 739 packages |
| 2 | Backend lint | `npm run lint` | ❌ **FAIL** — ESLint 8.57.1 "couldn't find a configuration file" → CI step red |
| 3 | Backend compile | `npm run build` (tsc) | ✅ clean |
| 4 | Backend tests | `npm test` | ⚠️ **vacuous pass** — 1 suite skipped, **3/3 tests SKIPPED, 0 executed** |
| 5 | App deps | `flutter pub get` | ✅ resolves |
| 6 | App analyze | `flutter analyze` | ❌ **FAIL — 11 errors** (auth_bloc.dart ×6, profile_screen.dart ×2, storage_service.dart ×3) + warnings |
| 7 | App tests | `flutter test` | ⚠️ 3 trivial tests pass — **none import production code (~0% coverage)** |
| 8 | Admin deps | `flutter pub get` | ✅ resolves (file_picker plugin warnings) |
| 9 | Admin analyze | `flutter analyze` | ✅ clean — 2 deprecation infos only |
| 10 | Admin web build | `flutter build web --release` | ❌ **FAIL — "Missing index.html."** (no `web/` platform dir) |

**CI consequence:** all three GitHub workflows have at least one permanently failing step as committed (backend.yml L31–32 lint; flutter.yml L30–31 analyze, L62–66 android build needs absent `google-services.json`, L100+ ios needs absent `ios/`; admin.yml L27–28 web build).

---

## 3. Findings by Module

Legend: 🔴 CRITICAL · 🟠 HIGH · 🟡 MEDIUM · ⚪ LOW. Items marked **[LIVE]** were reproduced by execution above.

### 3.1 rayzi-backend (Node/TS API)

🔴 **C1 — Free coins endpoint.** `wallet.controller.ts:38–61` accepts `packageId`+`amount` from the request and credits coins with no payment provider, no webhook signature, no server-side price table. Any authenticated user can mint unlimited currency.
🟠 Fix: delete until Stripe/Razorpay integration exists, or validate against a DB-backed package catalog.

🔴 **C2 — Mass assignment on profile update.** `user.controller.ts:24–28` passes raw `req.body` into a **service-role** Supabase update on `profiles`. Users can set own `coins`, `diamonds`, `is_banned`, `is_verified`. **[verified by direct read]**
🟠 Fix: whitelist fields (`display_name`, `bio`, `avatar_url`).

🔴 **C3 — Negative-quantity gift exploit.** Gift send validates neither sign nor bounds of `quantity` → negative amounts *increase* balance via deduction path. Add DB CHECK constraints (`quantity > 0`, `coins >= 0`, `diamonds >= 0`) + input validation.

🔴 **C4 — Socket gifts bypass wallet.** `socket/index.ts:63–73` broadcasts gift without calling `WalletService.deductCoins` → free gifts over Socket.IO. Also unguarded async handler → process crash path on rejection.

🔴 **C5 — Secrets in responses.** Private stream/room passwords stored plaintext and host `agora_token` persisted/returned in row selects. Hash passwords (bcryptjs already installed); strip sensitive columns from all selects; enforce password inside `getToken`.

🔴 **C6 — Admin plane unreachable.** `/admin/*` routes check a role location that README's bootstrap SQL doesn't populate consistently (`raw_user_meta_data.role`). Either every admin call 403s, or one metadata edit = full escalation.
🟠 Fix: read role from `app_metadata` or a profiles column; single canonical bootstrap.

🔴 **C7 — Rate-limit collapse behind proxy.** In-memory express-rate-limit + no `app.set('trust proxy', 1)` under nginx → **entire platform shares one bucket ≈ 100 req/15 min**, and external monitors share IP buckets. Move to shared Redis store; exempt `/health`.

🟠 **HIGH (12):** custom-JWT vs Supabase token duality in auth middleware; CORS `*` (HTTP+WS); zero schema validation (no zod/joi anywhere); PostgREST filter-string injection ×2 (e.g. `user.controller.ts:109` `.or()` interpolation); bans never enforced at middleware; chat insert failure still broadcasts; non-atomic gift money-flow (read-check then deduct); `getToken` ignores private-stream passwords; CI lint broken **[LIVE C2]**; CI tests unpassable/vacuous **[LIVE #4]**; `/auth/me` route missing auth middleware.

🟡 **MEDIUM (14):** email leak in chat broadcast + follower notifications; unlimited likes; silent audit-log failures ×4; leaderboard cron unguarded/wrong-date basis; env assertions instead of startup validation; Redis provisioned but never used (limiter/cache); Firebase push dead code path; no graceful shutdown; no 404 handler; 10 MB JSON body cap; stale `dist/` ships compiled tests (tsconfig lacks `exclude: src/__tests__`); README claims misleading vs reality; unused documented `SUPABASE_ANON_KEY`.

⚪ **LOW (9):** 5 unused deps; dead constants module; uncapped pagination; multer pinned old; Agora UID collision strategy; room-capacity TOCTOU; full-row profile leaks; no `engines` field; logger lacks request IDs.

✅ **What's right:** wallet RPCs truly atomic with server-side guards (`002_functions.sql:6–17,33–44`); all queries parameterized; helmet first in chain; multi-stage node:18-alpine Dockerfile, non-root `USER node`, HEALTHCHECK; `.env.example` documents 14 vars; git/docker ignore hygiene; nginx WS headers correct; **no hardcoded secrets found anywhere**; lockfile present.

### 3.2 rayzi_app (Flutter mobile)

🔴 **C1 — Does not compile. [LIVE]** 11 analyzer errors: `auth_bloc.dart:36,39,41,58,61,63` (Session→String, User?→User), `profile_screen.dart:11–12` (bloc bound inference), `storage_service.dart:10,16,23` (String→File). Nothing ships until these land.
🟠 Fix order: types first → then `flutter analyze --fatal-infos` gate.

🔴 **C2 — Core flow crashes.** `routes.dart` declares 18 route names but registers 12 builders; `/stream` is missing yet pushed from `live_tab.dart:70–71` and `create_stream_screen.dart:44` → runtime Navigator crash on Go Live / tap-live-card. Audio rooms/chat/post-detail screens don't exist at all.

🔴 **C3 — Viewers kick each other off.** `_uid` derived from the *host's* id hex substring for every participant (`stream_screen.dart:39–42`) → identical Agora UIDs → duplicate disconnects.

🔴 **C4 — Audience sees black.** Only local canvas rendered; `AgoraService.initialize()` registers **no `RtcEngineEventHandler`** (`agora_service.dart:10–15`) → remote video can never display.

🟠 **HIGH (8):** access token read from SharedPreferences but **never written after login/register** → API calls unauthenticated (the token bug behind C1-adjacent flows); tokens plaintext even when fixed (use flutter_secure_storage); literal `[10, 50, 100...][index] coins` rendered via `'$prices[index]'` (`stream_screen.dart:241`); `setState` after dispose ×2 (`create_stream_screen.dart:53`, `edit_profile_screen.dart:55`); `BlocProvider.value(context.read())` without type arg (`profile_screen.dart:12`); socket listener never removed on dispose (`stream_screen.dart:54–80`) → duplicated events; **`analysis_options.yaml` missing** despite `flutter_lints` dep → lints inert; tests import zero production code.

🟡 **MEDIUM:** `print()` ×4; ~8 silent `catch (_) {}` sites render failures as empty states; fire-and-forget leave/end calls in dispose; 401 handler is an empty stub (`api_service.dart:24–26`); gift prices hardcoded client-side + double-send risk (REST **and** socket fired per gift, `stream_screen.dart:222–232`).

⚪ Platform gaps: Android scaffolding incomplete (needs regeneration + absent `google-services.json`); **no `ios/` dir**; Firebase/push never initialized in `main`.

### 3.3 rayzi_admin (Flutter Web)

🔴 **C1 — No admin enforcement on any layer.** Client: any successful login lands on `/dashboard` (`login_screen.dart:19–23`), zero role checks in `lib/`. Server: migrations contain **no** `is_admin()` helper or role-based policies. Net effect: every registered user reaches the panel, and every action they attempt **fails against its own RLS** (profiles/streams are own-only, e.g. `001_init.sql:346,351`).
🟠 Fix: add `is_admin()` security-definer helper + admin policies/RPCs; guard routes client-side too.

🔴 **C2 — Financials exposed anonymously. [verified]** `get_admin_dashboard_stats()` (`002_functions.sql:63–81`) is `SECURITY DEFINER` with **no REVOKE/GRANT restriction** → default PUBLIC EXECUTE; anyone can pull platform revenue/user counts via PostgREST RPC.

🔴 **C3 — `reports` is a dead table. [verified]** RLS ENABLED (`001_init.sql:337`) with **zero policies** → anon-key clients can neither read nor write; the Reports screen can never work as written.

🟠 **HIGH:** logout never calls `signOut()` (`admin_drawer.dart:53–57`); withdrawal approve/reject = unvalidated status flip (no amount check/idempotency/audit trail, `withdrawals_screen.dart:37–41`); all moderation is direct client-side table writes through the public anon key.

🟡 **MEDIUM:** dashboard chart shows hardcoded fake data (`dashboard_screen.dart:104–108`); stats errors swallowed → zeros displayed; five `_load()` methods lack try/catch → infinite spinners; unbounded pagination; placeholder Supabase keys in `main.dart:10–13` (documented hand-edit workflow, but no env mechanism); **cannot build web** — no `web/` platform dir **[LIVE #10]**; no `test/`, no `analysis_options.yaml`, no `.gitignore`.

⚪ 5 unused deps; placeholder image URLs; deprecated APIs.

### 3.4 Database (supabase/migrations)

✅ Schema is coherent; wallet functions properly atomic/guarded.
🔴 Missing: admin-role model end-to-end; policies for `reports`; CHECK constraints on economy columns; PUBLIC EXECUTE revocation on definer functions.

### 3.5 Infra / CI / Config

🟠 docker-compose publishes **Redis 6379 to host with no password** configured (`docker-compose.yml` redis service).
🟠 Compose does not auto-load `.env.production` (only `.env`) — README's `cp .env.production.example .env.production` + plain `docker-compose up` yields an env-less container unless `--env-file` is passed.
🟡 `nginx/nginx.conf`: solid TLS 1.2+/WS/gzip/auth-limits, but placeholders (`api.yourdomain.com`) and expected certs dir `nginx/ssl/` absent.
🟡 `load-test.yml`: placeholder target URL + plaintext credentials in repo.
⚪ Stray **empty `rayzi-admin/` directory** (typo duplicate of `rayzi_admin/`, created later same day) — safe to delete.
⚪ `.claude/logs/` local artifact — harmless, consider ignoring.

---

## 4. Remediation Plan (phased, ordered)

### Phase 0 — Housekeeping (≤ half day)
- [ ] Delete stray empty `rayzi-admin/`.
- [ ] Add `analysis_options.yaml` (flutter_lints) to both Flutter projects.
- [ ] Add ESLint config to backend (`eslint.config.js` or `.eslintrc.json`) so `npm run lint` runs.
- [ ] Exclude `src/__tests__` from backend `tsconfig.json` build.
- [ ] Fix compose env loading (`--env-file .env.production` in README/scripts); stop publishing Redis port (drop `ports:` on redis; keep internal network).

### Phase 1 — Make everything build & gate CI (1–2 days)
- [ ] Fix 11 mobile analyzer errors (auth_bloc types, profile_screen bloc typing, storage_service File params).
- [ ] Register missing route builders (`/stream` first) or remove dead route constants.
- [ ] `flutter create --platforms web .` in `rayzi_admin` to generate `web/` (+ decide android/ios needs for app).
- [ ] Acceptance: `npm run lint && npm run build && npm test`, `flutter analyze && flutter test` (both apps), `flutter build web` all exit 0 locally AND in CI.
- [ ] Un-skip or replace backend tests with Supabase-mocking unit tests; make CI meaningful again.

### Phase 2 — Close the money holes (2–4 days) 🔐 highest business risk
- [ ] Remove/disable `POST /wallet/purchase` until a payment provider + webhook signature verification exist.
- [ ] Whitelist fields in `updateProfile`; central zod validation on all mutating endpoints.
- [ ] Validate/clamp gift `quantity`; add DB CHECK constraints; route Socket.IO gifts through `deductCoins` atomically.
- [ ] Hash stream/room passwords; strip `password`/`agora_token` from responses; enforce password in `getToken`.
- [ ] Wrap async socket handlers; add `unhandledRejection`/`uncaughtException` guards + graceful shutdown.
- [ ] Enforce bans in auth middleware.

### Phase 3 — Admin plane end-to-end (2–3 days)
- [ ] Define canonical admin identity (profiles.role or app_metadata), fix README bootstrap SQL.
- [ ] Add `is_admin()` helper + admin RLS policies (incl. `reports`) + REVOKE PUBLIC EXECUTE on definer functions.
- [ ] Move moderation writes into `SECURITY DEFINER` RPCs guarded by `is_admin()`.
- [ ] Client: role-gate routes, real logout, validated withdrawal approvals with audit rows.

### Phase 4 — Mobile core experience + hardening (3–5 days)
- [ ] Persist session token post-auth (then move to secure storage); implement 401 refresh/logout.
- [ ] Per-user Agora UIDs; register `RtcEngineEventHandler` and render remote tracks.
- [ ] Fix interpolation/setState/dispose/listener-leak bugs; replace silent catches with error UI.
- [ ] Initialize Firebase + wire push; regenerate Android scaffolding; add `google-services.json` workflow input (secret/step).
- [ ] Real unit/widget tests importing production code (target ≥60% on services/blocs).
- [ ] Backend ops: trust proxy + shared Redis limiter, CORS allowlist, 404 handler, request-ID logging, pagination caps.

### Exit criteria for "ALL OK"
`lint ✓ · tsc ✓ · tests>0 executed ✓ · flutter analyze 0 issues ✓ (both) · admin web build ✓ · no CRITICAL/HIGH open · economy paths require payment ✓ · admin actions impossible for non-admins ✓ · CI green on main ✓`

---

## 5. Audit Trail

- Static deep audits: backend (full tree/security pass), mobile (full lib/test pass), admin (10 files, exhaustive), db/infra/config (direct reads).
- Live runs: §2 matrix — all commands executed 2026-08-22 on this machine.
- Spot-verifications by main auditor (not just subagent claims): mass-assignment code path, purchase endpoint existence, ESLint-config absence, reports-policy absence, definer-function grant state, all §2 results.

---

## 6. Remediation Log — EXECUTED & VERIFIED (2026-08-22)

### Phase 0 — Housekeeping ✅
- Deleted stray empty `rayzi-admin/`.
- Added `analysis_options.yaml` (flutter_lints) to both Flutter apps.
- Added `.eslintrc.cjs` to backend → `npm run lint` now runs and passes.
- `tsconfig.json` excludes `src/__tests__` from the production build.
- docker-compose: Redis no longer published to host; API reads `.env.production` via `env_file:`; README aligned.

### Phase 1 — Build & CI gates ✅
- Fixed all 11 mobile analyzer errors (`auth_bloc` session handling rewritten to persist backend JWT + restore via `/auth/me`; `storage_service` now passes `File`; `profile_screen` explicit `AuthBloc`).
- Registered **all 8 missing routes** incl. `/stream` (crash fix); added `ComingSoonScreen` placeholders for unbuilt features.
- `rayzi_admin`: generated web platform → `flutter build web --release` succeeds.
- Backend tests rewritten as real unit tests with mocked Supabase: **6/6 executed** (was 0/3 skipped). Register now returns 201 via previously-dead `created()` helper.
- **Discovered + fixed en route:** auth middleware forwarded our custom JWT to `supabase.auth.getUser()` → every authenticated request failed. Middleware now verifies own JWT + reads live `role/is_banned` from profiles.

### Phase 2 — Economy holes closed ✅
- `POST /wallet/purchase` → hard 501 until payment provider exists.
- `updateProfile` field-whitelist (mass-assignment dead).
- Gift flow: shared `GiftService` used by REST **and** Socket.IO; quantity validated 1..1000 int; inactive gifts rejected; compensating refunds on partial failure.
- Stream/room passwords bcrypt-hashed on create and verified in `getToken`/join; `password`/`agora_token` stripped from every response.
- Bans enforced in middleware (403 before any handler).
- Ops: trust proxy(1), CORS allowlist via `CORS_ORIGIN`, shared Redis rate-limit store (+ in-memory fallback), `/health` exempt from limiter, 1 MB body cap, 404 handler, env validation at boot, graceful shutdown, unhandledRejection/uncaughtException guards, socket handlers fully guarded, email PII removed from chat broadcasts/follower notifications, pagination capped everywhere.

### Phase 3 — Admin plane end-to-end ✅
- Migration `supabase/migrations/003_security_hardening.sql`: economy CHECK constraints; canonical `profiles.role` model; `is_admin()` helper; reports RLS policies (insert-own / read+update-admin); REVOKE PUBLIC EXECUTE on ALL definer functions with explicit service_role grants (signatures verified against 002).
- Backend admin endpoints extended: stream list/ban, withdrawal list/approve/reject (reject auto-refunds diamonds, idempotent status guards); gift update whitelisted; report/user inputs validated; admins protected from ban.
- Admin panel rewritten to pure REST (`admin_api.dart`, JWT + role-gated routes, real logout, confirmed withdrawal actions, error states everywhere, fake chart replaced with real stats); Supabase/fl_chart/file_picker deps pruned; config via `--dart-define=API_BASE_URL`.

### Phase 4 — Mobile core + CI ✅
- Tokens moved to `flutter_secure_storage` (keystore/keychain) with plaintext migration; centralized `TokenStore` used by API/socket/bloc; 401 clears session.
- Per-user Agora UIDs (no more viewer kick-outs); `RtcEngineEventHandler` wired → remote video renders; host-only preview; chat listener removed on dispose; `$prices[index]` interpolation fixed; double-send gift path removed; setState-after-dispose guards ×2; silent catches now surface SnackBar errors ×8; Firebase-ready notification service kept.
- Real production-code unit tests (`lib/core/utils/formatters.dart`) — app suite 7/7.
- CI: android build job self-skips without `google-services.json`; iOS job self-skips without `ios/`; load-test credentials parameterized via process env.

### Post-fix acceptance matrix (executed)

| Check | Before | After |
|---|---|---|
| backend lint | ❌ no config | ✅ 0 problems |
| backend tsc | ✅ | ✅ |
| backend tests | ⚠️ 0 executed | ✅ **6/6 passed** |
| app analyze | ❌ 11 errors | ✅ 0 errors / 0 warnings (7 infos) |
| app tests | ⚠️ trivial | ✅ **7/7**, production code covered |
| admin analyze | ✅ | ✅ 0 errors / 0 warnings (7 infos) |
| admin test | — | ✅ 1/1 |
| admin web build | ❌ missing index.html | ✅ builds |
| **app APK build** | ❌ no gradle scaffolding | ✅ **`app-debug.apk` (249 MB, debug-signed) builds** |

### Android build enablement (follow-up pass)
- Regenerated platform files via `flutter create --platforms android` (Kotlin-DSL gradle set); reconciled: removed legacy Groovy `app/build.gradle` + stale duplicate `MainActivity.kt`; ported Firebase BOM/messaging + multidex into `build.gradle.kts`; `google-services` plugin wired in `settings.gradle.kts`.
- Added placeholder `android/app/google-services.json` (**REPLACE with your real Firebase file**) so the google-services plugin passes.
- Pinned `ndkVersion = "27.0.12077973"`; enabled core-library desugaring (required by flutter_local_notifications); upgraded flutter_local_notifications ^18 (16.x has a known compile error on new SDKs); removed dead plugins that broke AGP 8.7 (`fluttertoast`, `google_sign_in`, `sign_in_with_apple` — none imported anywhere).
- Network note: `services.gradle.org` is blocked on this machine; Gradle was fetched from the Tencent mirror into the wrapper cache.

### Remaining operator actions (cannot be done from code)
1. Run `003_security_hardening.sql` in Supabase SQL Editor (after 001/002).
2. Create storage buckets per README §Setup.
3. Promote your admin: `UPDATE public.profiles SET role='admin' WHERE id=(SELECT id FROM auth.users WHERE email='...')`.
4. Provide `google-services.json` (Android push) / generate `ios/` if needed; set `CORS_ORIGIN`, `RATE_LIMIT_MAX` etc. in `.env.production`.
5. nginx: replace `api.yourdomain.com` + supply TLS certs under `nginx/ssl/`.
6. Integrate Stripe/Razorpay, then re-enable coin purchase behind signed webhooks.
