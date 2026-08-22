# Rayzi Clone — Live Streaming App

Full-stack live streaming platform (Smarty/Rayzi clone): Node.js API + Supabase + Flutter mobile app + Flutter Web admin panel + Agora RTC + Socket.IO.

## Structure

```
├── rayzi-backend/       # Node.js + Express + Socket.IO API (TypeScript)
├── rayzi_app/           # Flutter mobile app (iOS/Android)
├── rayzi_admin/         # Flutter Web admin dashboard
├── supabase/
│   ├── migrations/      # SQL schema, RLS, triggers, functions
│   └── functions/       # Edge Functions (agora-token, send-notification)
├── nginx/nginx.conf     # Reverse proxy config
├── docker-compose.yml   # api + redis + nginx
├── .github/workflows/   # CI/CD (backend, flutter, admin)
└── load-test.yml        # Artillery load test
```

## Prerequisites

- Node.js >= 18, npm >= 9
- Flutter >= 3.19, Dart >= 3.3
- Supabase / Agora / Firebase accounts (see spec section 2)

## Setup

### 1. Database
Run `supabase/migrations/001_init.sql` then `002_functions.sql` in the Supabase SQL Editor.
Create storage buckets: `avatars`, `stream-thumbnails`, `post-media`, `gift-animations`, `room-covers` (all public).

### 2. Backend
```bash
cd rayzi-backend
cp .env.example .env        # fill in your keys
npm install
npm run dev                 # http://localhost:3000/health
```

### 3. Mobile App
```bash
flutter create --org com.yourcompany .   # generate remaining platform files once
# edit lib/config/constants.dart with your URLs/keys
flutter pub get
flutter run
```
Add `google-services.json` to `android/app/` for push notifications.

### 4. Admin Panel
```bash
cd rayzi_admin
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000
```
The panel talks to the backend `/admin/*` REST API (JWT-authenticated, role-enforced server-side) — no Supabase keys are embedded in the client.

### 5. Docker (production)
```bash
cp .env.production.example .env.production   # fill in values
docker-compose up -d --build                 # compose reads .env.production via env_file
```
Note: Redis is internal-only (no host port published); reach it from inside the `rayzi-network`.

## Testing
```bash
cd rayzi-backend && npm test          # backend unit tests (Supabase mocked)
cd rayzi_app && flutter test          # flutter unit tests
artillery run load-test.yml           # load testing
```

## Key Endpoints
See the API reference in `rayzi_clone_cli_spec.md` §11.2 and Socket.IO events in §11.3.

## Admin Access
The canonical admin flag lives in `profiles.role` (added by `003_security_hardening.sql`). Promote a user after they've logged in at least once (so the profile row exists):
```sql
UPDATE public.profiles SET role = 'admin'
WHERE id = (SELECT id FROM auth.users WHERE email = 'your-admin@email.com');
```

License: MIT
