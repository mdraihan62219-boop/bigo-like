-- 004_seed_example_reels.sql
-- Seeds example reels (TikTok-style short videos) into public.posts.
-- Safe to re-run: previously seeded example reels are replaced.
--
-- NOTE: This file is also applied programmatically by
-- rayzi-backend/scripts/seed-reels.mjs (uses SUPABASE_URL +
-- SUPABASE_SERVICE_ROLE_KEY from rayzi-backend/.env). Prefer running that
-- script; it resolves an existing profile automatically and works with RLS.

-- Idempotency marker: all example reels carry this content prefix.
-- Example reels are attributed to the oldest existing profile so the
-- posts_user_id_fkey constraint is satisfied without creating auth users.

DO $$
DECLARE
  demo_profile_id UUID;
  example_prefix TEXT := '[PHM Example]';
BEGIN
  SELECT id INTO demo_profile_id FROM public.profiles ORDER BY created_at ASC LIMIT 1;

  IF demo_profile_id IS NULL THEN
    RAISE NOTICE 'No profiles found — register a user first, then re-run this seed.';
    RETURN;
  END IF;

  DELETE FROM public.posts WHERE content LIKE example_prefix || '%';

  INSERT INTO public.posts (user_id, content, media_urls, media_type, likes_count, comments_count, shares_count) VALUES
    (demo_profile_id, example_prefix || ' Welcome to PHM Live! Your Stage, Your Stream, Your Earning 🎬',
     ARRAY['https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'], 'video', 1284, 56, 23),
    (demo_profile_id, example_prefix || ' Dance challenge night — drop your best move in the comments 💃',
     ARRAY['https://storage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4'], 'video', 942, 41, 12),
    (demo_profile_id, example_prefix || ' Behind the scenes of tonight''s PK battle 🔥 Who wins?',
     ARRAY['https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4'], 'video', 2310, 187, 64),
    (demo_profile_id, example_prefix || ' Go live in one tap and start earning diamonds 💎',
     ARRAY['https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4'], 'video', 1755, 92, 38),
    (demo_profile_id, example_prefix || ' Weekend vibes on PHM Live ✨ Tag someone who needs this feed',
     ARRAY['https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4'], 'video', 640, 27, 9),
    (demo_profile_id, example_prefix || ' Voice rooms are open — come hang out with us 🎙️',
     ARRAY['https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4'], 'video', 1122, 74, 31);

  RAISE NOTICE 'Seeded % example reels for profile %', 6, demo_profile_id;
END $$;
