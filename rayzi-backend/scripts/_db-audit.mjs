import 'dotenv/config'
const ANON = { apikey: process.env.SUPABASE_ANON_KEY, Authorization: `Bearer ${process.env.SUPABASE_ANON_KEY}`, 'Content-Type': 'application/json' }
const base = process.env.SUPABASE_URL + '/rest/v1'

async function probe(label, path, method = 'GET', body) {
  const res = await fetch(`${base}/${path}`, {
    method,
    headers: { ...ANON, ...(method !== 'GET' ? { Prefer: 'return=minimal' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  })
  let j = null
  try { j = await res.json().catch(() => null) } catch (_) {}
  const msg = j && typeof j === 'object' ? (j.message ?? j.error ?? '') : ''
  console.log(`${res.status}  ${label}${msg ? ' — ' + String(msg).slice(0, 110) : ''}`)
}

// table existence + anon read
await probe('posts exists+anon read', 'posts?select=id&limit=1')
await probe('stories', 'stories?select=id&limit=1')
await probe('story_views', 'story_views?select=story_id&limit=1')
await probe('friend_requests', 'friend_requests?select=id&limit=1')
await probe('shop_items', 'shop_items?select=id&limit=1')
await probe('user_inventory', 'user_inventory?select=id&limit=1')
await probe('reseller_agents', 'reseller_agents?select=id&limit=1')
await probe('recharge_requests', 'recharge_requests?select=id&limit=1')
await probe('host_applications', 'host_applications?select=id&limit=1')
await probe('pk_matchmaking_queue', 'pk_matchmaking_queue?select=id&limit=1')
await probe('pk_dragon_stages', 'pk_dragon_stages?select=stage&limit=5')
await probe('conversations', 'conversations?select=id&limit=1')
await probe('messages', 'messages?select=id&limit=1')

// new columns exist?
await probe('profiles v2 columns', 'profiles?select=id,equipped_frame_id,equipped_badge_id,name_effect,camera_prefs&limit=1')
await probe('posts v2 columns', 'posts?select=id,visibility,is_removed&limit=1')
await probe('pk_battles dragon columns', 'pk_battles?select=id,dragon_stage_1,duration_seconds&limit=1')

// RLS evidence: anon writes should be DENIED on every new table
await probe('anon insert stories (expect deny)', 'stories', 'POST', { author_id: '00000000-0000-0000-0000-000000000000', media_url: 'x' })
await probe('anon insert shop_items (expect deny)', 'shop_items', 'POST', { category: 'badge', name: 'anon-probe', price_diamonds: 1 })
await probe('anon insert conversations (expect deny)', 'conversations', 'POST', {})
await probe('anon insert recharge_requests (expect deny)', 'recharge_requests', 'POST', { requester_id: '00000000-0000-0000-0000-000000000000', diamonds_requested: 1 })
await probe('anon update inventory (expect deny)', 'user_inventory?id=eq.00000000-0000-0000-0000-000000000000', 'PATCH', { is_equipped: true })
