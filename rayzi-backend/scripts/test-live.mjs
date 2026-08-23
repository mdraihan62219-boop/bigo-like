#!/usr/bin/env node
// Live integration smoke test for PHM Live v2 endpoints.
// Usage: node scripts/test-live.mjs [baseUrl]
// Creates a throwaway confirmed user via the admin API (no signup email,
// so Supabase rate limits never block the run), logs in through
// /auth/login, walks every v2 endpoint group, prints PASS/FAIL per check.
import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'

const PURGE_ALL = process.argv.includes('--purge')
const BASE = process.argv.slice(2).find((a) => !a.startsWith('--')) || 'https://bigo-like-1.onrender.com'
const API = `${BASE}/api/v1`

let token = null
let results = []
let createdUserId = null

function check(name, ok, detail = '') {
  results.push({ name, ok, detail })
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`)
}

async function req(method, path, body, auth = true) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(auth && token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  let json = null
  try { json = await res.json() } catch (_) {}
  return { status: res.status, json }
}

async function main() {
  console.log(`Target: ${API}\n`)

  // ---------- health ----------
  try {
    const r = await fetch(`${BASE}/health`)
    const j = await r.json()
    check('GET /health', j.status === 'ok')
  } catch (e) { check('GET /health', false, e.message) }

  // ---------- auth: create confirmed test user (admin API) + real login ----------
  const suffix = Date.now().toString(36)
  const email = `phm.live.test+${suffix}@gmail.com`
  const password = `Test-${suffix}-Pass!`
  const username = `phtmtest${suffix}`.slice(0, 20)

  const supabaseUrl = process.env.SUPABASE_URL
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!supabaseUrl || !serviceKey) {
    console.log('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing in rayzi-backend/.env')
    report()
    return
  }
  const adminClient = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } })
  const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
    email, password, email_confirm: true,
    user_metadata: { username, display_name: 'PHM Live Test' },
  })
  check('admin createUser', !createErr && !!created?.user, createErr?.message ?? '')
  createdUserId = created?.user?.id ?? null

  let r
  r = await req('POST', '/auth/login', { email, password }, false)
  check('POST /auth/login', r.json?.success === true && !!r.json?.data?.token, JSON.stringify(r.json?.error ?? ''))
  token = r.json?.data?.token

  if (!token) {
    console.log('\nNo token — cannot continue authenticated checks.')
    report()
    return
  }

  // ---------- leaderboard ----------
  r = await req('GET', '/leaderboard?type=gifters&period=all')
  check('GET /leaderboard', r.json?.success === true && Array.isArray(r.json?.data), JSON.stringify(r.json?.error ?? ''))

  // ---------- shop ----------
  r = await req('GET', '/shop/items')
  check('GET /shop/items', r.json?.success === true && Array.isArray(r.json?.data) && r.json.data.length > 0,
    `${r.json?.data?.length ?? 0} items`)
  const vipItem = (r.json?.data ?? []).find((i) => i.tier === 'vip' && i.category === 'badge')

  // purchase with zero balance must fail CLEANLY (server-side wallet check)
  r = await req('POST', '/shop/purchase', { item_id: vipItem?.id })
  check('POST /shop/purchase (0 diamonds) rejects cleanly',
    r.json?.success === false && /insufficient/i.test(r.json?.error ?? ''), r.json?.error)

  r = await req('GET', '/inventory')
  check('GET /inventory', r.json?.success === true && Array.isArray(r.json?.data), JSON.stringify(r.json?.error ?? ''))

  // ---------- feed ----------
  r = await req('GET', '/feed/posts?scope=all')
  check('GET /feed/posts (all)', r.json?.success === true && Array.isArray(r.json?.data), JSON.stringify(r.json?.error ?? ''))
  check('  seeded example reels visible', (r.json?.data ?? []).length >= 6, `${r.json?.data?.length ?? 0} posts`)

  r = await req('GET', '/feed/posts?scope=timeline')
  check('GET /feed/posts (timeline)', r.json?.success === true && Array.isArray(r.json?.data), JSON.stringify(r.json?.error ?? ''))

  r = await req('POST', '/feed/posts', { content: `Smoke test post ${suffix}` })
  check('POST /feed/posts', r.json?.success === true && !!r.json?.data?.id, JSON.stringify(r.json?.error ?? ''))
  const postId = r.json?.data?.id

  if (postId) {
    r = await req('POST', `/feed/posts/${postId}/like`)
    check('POST /feed/posts/:id/like', r.json?.success === true, JSON.stringify(r.json?.error ?? ''))
    r = await req('DELETE', `/feed/posts/${postId}/like`)
    check('DELETE /feed/posts/:id/like', r.json?.success === true, JSON.stringify(r.json?.error ?? ''))
    r = await req('POST', `/feed/posts/${postId}/comments`, { content: 'nice' })
    check('POST /feed/posts/:id/comments', r.json?.success === true, JSON.stringify(r.json?.error ?? ''))
    r = await req('GET', `/feed/posts/${postId}/comments`)
    check('GET /feed/posts/:id/comments', r.json?.success === true && Array.isArray(r.json?.data), JSON.stringify(r.json?.error ?? ''))
    r = await req('DELETE', `/feed/posts/${postId}`)
    check('DELETE /feed/posts/:id (own)', r.json?.success === true, JSON.stringify(r.json?.error ?? ''))
  }

  r = await req('GET', '/feed/stories')
  check('GET /feed/stories', r.json?.success === true && Array.isArray(r.json?.data), JSON.stringify(r.json?.error ?? ''))

  // ---------- reseller ----------
  r = await req('POST', '/reseller/recharge-request', { diamonds_requested: 500 })
  check('POST /reseller/recharge-request', r.json?.success === true, JSON.stringify(r.json?.error ?? ''))
  r = await req('POST', '/reseller/recharge-request', { diamonds_requested: 100 })
  check('  duplicate pending rejected', r.json?.success === false && /pending/.test(r.json?.error ?? ''), r.json?.error)
  r = await req('GET', '/reseller/my-requests')
  check('GET /reseller/my-requests', r.json?.success === true && Array.isArray(r.json?.data) && r.json.data.length === 1,
    JSON.stringify(r.json?.error ?? ''))

  // ---------- host application ----------
  r = await req('POST', '/host-application', { full_name: 'Test Host', phone_number: '+8801700000000' })
  check('POST /host-application', r.json?.success === true, JSON.stringify(r.json?.error ?? ''))
  r = await req('GET', '/host-application/me')
  check('GET /host-application/me', r.json?.success === true && r.json?.data?.status === 'pending', JSON.stringify(r.json?.error ?? ''))

  // ---------- friends ----------
  r = await req('GET', '/users/search?q=dfg')
  let otherUserId = null
  if (r.json?.success && Array.isArray(r.json.data)) {
    const other = r.json.data.find((u) => u.id && u.username !== username)
    otherUserId = other?.id ?? null
  }
  if (!otherUserId) {
    // Fall back to the seeded demo profile via anon REST.
    try {
      const { SUPABASE_URL, SUPABASE_ANON_KEY } = process.env
      if (SUPABASE_URL && SUPABASE_ANON_KEY) {
        const pr = await fetch(`${SUPABASE_URL}/rest/v1/profiles?select=id,username&limit=5`, {
          headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${SUPABASE_ANON_KEY}` },
        })
        const profiles = await pr.json()
        otherUserId = profiles?.find((p) => p.username !== username)?.id ?? null
      }
    } catch (_) {}
  }
  check('friend target found', !!otherUserId, otherUserId ?? 'no users')

  if (otherUserId) {
    r = await req('POST', `/friends/request/${otherUserId}`)
    check('POST /friends/request/:userId', r.status === 200 || r.status === 201, JSON.stringify(r.json))
    r = await req('GET', '/friends/count/' + otherUserId)
    check('GET /friends/count/:userId', r.json?.success === true && typeof r.json?.data?.count === 'number', JSON.stringify(r.json?.error ?? ''))
    r = await req('GET', '/friends')
    check('GET /friends', r.json?.success === true && Array.isArray(r.json?.data), JSON.stringify(r.json?.error ?? ''))
  }

  // ---------- profile extras ----------
  r = await req('GET', '/profile/summary')
  check('GET /profile/summary', r.json?.success === true && r.json?.data?.id, JSON.stringify(r.json?.error ?? ''))
  check('  summary has friends_count', typeof r.json?.data?.friends_count === 'number')

  r = await req('PUT', '/profile/theme', { item_id: vipItem?.id })
  check('PUT /profile/theme (unowned) rejected', r.json?.success === false, r.json?.error)

  r = await req('PUT', '/profile/camera-prefs', { filter: 'vivid', beauty_level: 30, brightness: 10 })
  check('PUT /profile/camera-prefs', r.json?.success === true && r.json?.data?.filter === 'vivid', JSON.stringify(r.json?.error ?? ''))

  r = await req('GET', '/profile/camera-prefs-persist-check', undefined, false).catch(() => ({}))
  // re-read summary to confirm persistence
  r = await req('GET', '/profile/summary')
  check('  camera prefs persisted', r.json?.data?.camera_prefs?.filter === 'vivid', JSON.stringify(r.json?.data?.camera_prefs ?? {}))

  // ---------- inbox ----------
  r = await req('GET', '/inbox/conversations')
  check('GET /inbox/conversations', r.json?.success === true && Array.isArray(r.json?.data), JSON.stringify(r.json?.error ?? ''))

  if (otherUserId) {
    r = await req('POST', `/inbox/conversations/open/${otherUserId}`)
    check('POST /inbox/conversations/open/:userId', r.json?.success === true && !!r.json?.data?.id, JSON.stringify(r.json?.error ?? ''))
    const convId = r.json?.data?.id
    if (convId) {
      r = await req('POST', `/inbox/conversations/${convId}/messages`, { message_type: 'text', text_content: 'hello from smoke test' })
      check('POST inbox text message', r.json?.success === true, JSON.stringify(r.json?.error ?? ''))
      r = await req('POST', `/inbox/conversations/${convId}/messages`, { message_type: 'video_reel', media_url: 'https://x/y.mp4', media_duration_seconds: 61 })
      check('  61s reel rejected server-side', r.json?.success === false && /60/.test(r.json?.error ?? ''), r.json?.error)
      r = await req('POST', `/inbox/conversations/${convId}/messages`, { message_type: 'video_reel', media_url: 'https://x/y.mp4', media_duration_seconds: 45 })
      check('  45s reel accepted', r.json?.success === true, JSON.stringify(r.json?.error ?? ''))
      r = await req('GET', `/inbox/conversations/${convId}/messages`)
      check('GET inbox messages', r.json?.success === true && Array.isArray(r.json?.data) && r.json.data.length >= 2, `${r.json?.data?.length ?? 0} msgs`)
      r = await req('POST', `/inbox/conversations/${convId}/call`, { call_type: 'video' })
      // 503 = Agora unconfigured (fail-fast, correct); 200/201 = configured + token issued.
      check('POST inbox call', r.status === 503 || r.json?.success === true,
        `${r.status} ${JSON.stringify(r.json?.error ?? '')}`)
      r = await req('PUT', `/inbox/conversations/${convId}/read`)
      check('PUT inbox read', r.json?.success === true, JSON.stringify(r.json?.error ?? ''))
    }
  }

  // ---------- pk ----------
  r = await req('POST', '/pk/queue', { stream_id: '00000000-0000-0000-0000-000000000000' })
  check('POST /pk/queue (bogus stream) rejects cleanly', r.json?.success === false, r.json?.error)
  r = await req('GET', '/pk/dragon-stages')
  check('GET /pk/dragon-stages', r.json?.success === true && Array.isArray(r.json?.data) && r.json.data.length === 5,
    `${r.json?.data?.length ?? 0} stages`)

  // ---------- legacy regression ----------
  r = await req('GET', '/posts?media_type=video')
  check('GET /posts (legacy reels, guest-safe)', r.json?.success === true && Array.isArray(r.json?.data), JSON.stringify(r.json?.error ?? ''))
  r = await req('GET', '/streams?status=live&following=true')
  check('GET /streams?following=true', r.json?.success === true && Array.isArray(r.json?.data), JSON.stringify(r.json?.error ?? ''))

  report()
}

function report() {
  const failed = results.filter((x) => !x.ok)
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`)
  if (failed.length) {
    console.log('FAILED:')
    for (const f of failed) console.log(`  - ${f.name}${f.detail ? ` (${f.detail})` : ''}`)
    // Not process.exit() here — that would skip the cleanup in finally.
    process.exitCode = 1
  }
}

main().catch((e) => {
  console.error(e)
  process.exitCode = 1
}).finally(async () => {
  // Never leave smoke-test junk in the production project.
  // NOTE: GoTrue's own cascade fails for our users ("Database error deleting
  // user"), so dependent rows are removed manually before deleting the user.
  try {
    const { createClient } = await import('@supabase/supabase-js')
    const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } })
    if (createdUserId) {
      await manualCascade(admin, createdUserId)
      const { error: delErr } = await admin.auth.admin.deleteUser(createdUserId)
      console.log(delErr ? `cleanup failed for ${createdUserId}: ${delErr.message}` : `cleaned up test user ${createdUserId}`)
    }
    if (PURGE_ALL) {
      let page = 1
      let purged = 0
      for (;;) {
        const { data } = await admin.auth.admin.listUsers({ page, perPage: 200 })
        const users = data?.users ?? []
        if (users.length === 0) break
        for (const u of users) {
          if (/^(phm\.live\.|phm\.audit|phm\.deploy)/.test(u.email ?? '')) {
            await manualCascade(admin, u.id)
            const { error } = await admin.auth.admin.deleteUser(u.id)
            if (!error) purged++
          }
        }
        page++
        if (page > 20) break
      }
      console.log(`purged ${purged} legacy smoke-test users`)
    }
  } catch (e) {
    console.warn('cleanup warning:', e.message)
  }
})

async function manualCascade(admin, userId) {
  try {
    const convs = await admin.from('conversations').select('id').or(`user_a_id.eq.${userId},user_b_id.eq.${userId}`)
    const ids = (convs.data ?? []).map((c) => c.id)
    if (ids.length > 0) {
      await admin.from('messages').delete().in('conversation_id', ids)
      await admin.from('conversations').delete().in('id', ids)
    }
    for (const [table, col] of [
      ['post_likes', 'user_id'], ['post_comments', 'user_id'], ['posts', 'user_id'],
      ['recharge_requests', 'requester_id'], ['host_applications', 'user_id'],
      ['user_inventory', 'user_id'], ['stories', 'author_id'],
    ]) {
      await admin.from(table).delete().eq(col, userId)
    }
    await admin.from('friend_requests').delete().or(`requester_id.eq.${userId},addressee_id.eq.${userId}`)
  } catch (_) {
    // Best-effort; deleteUser reports its own failure if something remains.
  }
}
