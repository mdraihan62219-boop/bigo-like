#!/usr/bin/env node
// Ensures every Supabase Storage bucket documented in README §Setup exists
// and is public: post-media, avatars, stream-thumbnails, gift-animations,
// room-covers. Idempotent — safe to run repeatedly.
//
// NOTE on write access: app users hold a custom backend JWT, not a Supabase
// session, so direct client-side uploads evaluate as `anon`. Uploads are
// therefore proxied through POST /api/v1/uploads (backend service role,
// JWT-authenticated, size/type whitelisted). Buckets stay public-read for
// display.
import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'

const url = process.env.SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
if (!url || !serviceKey) {
  console.error('Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY in rayzi-backend/.env')
  process.exit(1)
}
const supabase = createClient(url, serviceKey, { auth: { persistSession: false } })

const REQUIRED_BUCKETS = ['post-media', 'avatars', 'stream-thumbnails', 'gift-animations', 'room-covers']

async function main() {
  const { data: buckets, error } = await supabase.storage.listBuckets()
  if (error) throw new Error(`listBuckets failed: ${error.message}`)
  const existing = new Set((buckets ?? []).map((b) => b.name))

  for (const name of REQUIRED_BUCKETS) {
    if (existing.has(name)) {
      console.log(`exists: ${name}`)
      continue
    }
    const { error: createError } = await supabase.storage.createBucket(name, { public: true })
    if (createError) throw new Error(`createBucket(${name}) failed: ${createError.message}`)
    console.log(`created public bucket: ${name}`)
  }

  // Verify all are public.
  const { data: after } = await supabase.storage.listBuckets()
  for (const name of REQUIRED_BUCKETS) {
    const b = after?.find((x) => x.name === name)
    if (!b) throw new Error(`${name} missing after setup`)
    if (!b.public) throw new Error(`${name} is not public`)
  }
  console.log(`All ${REQUIRED_BUCKETS.length} buckets present and public.`)
}

main().catch((e) => {
  console.error(e.message)
  process.exit(1)
})
