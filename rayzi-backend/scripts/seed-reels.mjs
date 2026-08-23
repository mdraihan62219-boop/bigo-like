#!/usr/bin/env node
import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'
import { pipeline } from 'node:stream/promises'
import { createWriteStream } from 'node:fs'
import { readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const url = process.env.SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !serviceKey) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in rayzi-backend/.env')
  process.exit(1)
}

const supabase = createClient(url, serviceKey, { auth: { persistSession: false } })

const EXAMPLE_PREFIX = '[PHM Example]'
const BUCKET = 'post-media'
const FOLDER = 'example-reels'

// Verified reachable sample videos (test-videos.co.uk, CC-licensed test clips).
const sources = [
  {
    file: 'phm-welcome.mp4',
    src: 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_5MB.mp4',
    content: `${EXAMPLE_PREFIX} Welcome to PHM Live! Your Stage, Your Stream, Your Earning 🎬`,
    likes: 1284, comments: 56, shares: 23,
  },
  {
    file: 'phm-dance-night.mp4',
    src: 'https://test-videos.co.uk/vids/sintel/mp4/h264/720/Sintel_720_10s_5MB.mp4',
    content: `${EXAMPLE_PREFIX} Dance challenge night — drop your best move in the comments 💃`,
    likes: 942, comments: 41, shares: 12,
  },
  {
    file: 'phm-pk-battle.mp4',
    src: 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_5MB.mp4',
    content: `${EXAMPLE_PREFIX} Behind the scenes of tonight's PK battle 🔥 Who wins?`,
    likes: 2310, comments: 187, shares: 64,
  },
  {
    file: 'phm-go-live.mp4',
    src: 'https://test-videos.co.uk/vids/jellyfish/mp4/h264/720/Jellyfish_720_10s_5MB.mp4',
    content: `${EXAMPLE_PREFIX} Go live in one tap and start earning diamonds 💎`,
    likes: 1755, comments: 92, shares: 38,
  },
  {
    file: 'phm-weekend-vibes.mp4',
    src: 'https://test-videos.co.uk/vids/sintel/mp4/h264/720/Sintel_720_10s_2MB.mp4',
    content: `${EXAMPLE_PREFIX} Weekend vibes on PHM Live ✨ Tag someone who needs this feed`,
    likes: 640, comments: 27, shares: 9,
  },
  {
    file: 'phm-voice-room.mp4',
    src: 'https://test-videos.co.uk/vids/jellyfish/mp4/h264/720/Jellyfish_720_10s_2MB.mp4',
    content: `${EXAMPLE_PREFIX} Voice rooms are open — come hang out with us 🎙️`,
    likes: 1122, comments: 74, shares: 31,
  },
]

async function downloadToTmp(src, destPath) {
  const res = await fetch(src)
  if (!res.ok || !res.body) throw new Error(`Download failed (${res.status}): ${src}`)
  await pipeline(res.body, createWriteStream(destPath))
}

async function main() {
  const { data: profiles, error: profileError } = await supabase
    .from('profiles')
    .select('id, username')
    .order('created_at', { ascending: true })
    .limit(1)

  if (profileError) throw new Error(`Failed to load profiles: ${profileError.message}`)
  if (!profiles?.length) {
    console.error('No profiles found — register a user first, then re-run this seed.')
    process.exit(1)
  }

  const demoProfile = profiles[0]
  console.log(`Seeding example reels for profile: ${demoProfile.username} (${demoProfile.id})`)

  // 0. Ensure the post-media bucket exists and is public.
  const { data: buckets } = await supabase.storage.listBuckets()
  if (!buckets?.some((b) => b.name === BUCKET)) {
    const { error: createError } = await supabase.storage.createBucket(BUCKET, { public: true })
    if (createError) throw new Error(`Failed to create ${BUCKET} bucket: ${createError.message}`)
    console.log(`Created public bucket: ${BUCKET}`)
  }

  // 1. Ensure example media exists in Supabase Storage (self-hosted, permanent).
  const mediaUrls = []
  for (const item of sources) {
    const objectPath = `${FOLDER}/${item.file}`
    const publicUrl = `${url}/storage/v1/object/public/${BUCKET}/${objectPath}`
    const head = await fetch(publicUrl, { method: 'HEAD' })
    if (!head.ok) {
      const tmp = join(tmpdir(), item.file)
      console.log(`Downloading ${item.src} ...`)
      await downloadToTmp(item.src, tmp)
      const bytes = await readFile(tmp)
      const { error: uploadError } = await supabase.storage.from(BUCKET).upload(objectPath, bytes, {
        upsert: true,
        contentType: 'video/mp4',
      })
      if (uploadError) throw new Error(`Storage upload failed for ${objectPath}: ${uploadError.message}`)
      console.log(`Uploaded ${objectPath} (${(bytes.length / 1024 / 1024).toFixed(1)} MB)`)
    } else {
      console.log(`${objectPath} already present in storage`)
    }
    mediaUrls.push([publicUrl])
  }

  // 2. Replace previously seeded example reels.
  const { error: deleteError } = await supabase
    .from('posts')
    .delete()
    .like('content', `${EXAMPLE_PREFIX}%`)

  if (deleteError) throw new Error(`Failed to clear old example reels: ${deleteError.message}`)

  // 3. Insert example reels pointing at hosted media.
  const rows = sources.map((r, i) => ({
    user_id: demoProfile.id,
    content: r.content,
    media_urls: mediaUrls[i],
    media_type: 'video',
    likes_count: r.likes,
    comments_count: r.comments,
    shares_count: r.shares,
  }))

  const { data: inserted, error: insertError } = await supabase.from('posts').insert(rows).select('id')

  if (insertError) throw new Error(`Failed to seed reels: ${insertError.message}`)
  console.log(`Seeded ${inserted.length} example reels.`)

  // 4. Verify every seeded reel's media URL serves bytes.
  for (const urls of mediaUrls) {
    const res = await fetch(urls[0], { headers: { Range: 'bytes=0-1023' } })
    if (!res.ok) throw new Error(`Media URL not reachable (${res.status}): ${urls[0]}`)
  }
  console.log('All example media URLs are reachable from storage.')

  const { count, error: countError } = await supabase
    .from('posts')
    .select('*', { count: 'exact', head: true })
    .eq('media_type', 'video')

  if (countError) throw new Error(`Verification failed: ${countError.message}`)
  console.log(`Verified: ${count} video posts now visible.`)
}

main().catch((err) => {
  console.error(err.message)
  process.exit(1)
})
