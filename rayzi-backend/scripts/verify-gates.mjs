import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'
const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } })
const BASE = 'https://bigo-like-1.onrender.com'
const API = `${BASE}/api/v1`

// fresh user
const email = `phm.verify+${Date.now().toString(36)}@gmail.com`
const pw = `Verify-${Date.now().toString(36)}-x!`
const { data: cu } = await admin.auth.admin.createUser({ email, password: pw, email_confirm: true })
const login = await fetch(`${API}/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pw }) })
const token = (await login.json())?.data?.token
const H = { Authorization: `Bearer ${token}` }

let pass = 0, total = 0
const check = (name, ok, detail = '') => { total++; if (ok) pass++; console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`) }

// ---- F-04: upload proxy end-to-end (real PNG bytes) ----
const png = Buffer.from('89504e470d0a1a0a0000000d494844520000000100000001080600000' + '01f15c4890000000d49444154789c6260000000060005' + '27de41ba0000000049454e44ae426082', 'hex')
const fd = new FormData()
fd.append('bucket', 'avatars')
fd.append('file', new Blob([png], { type: 'image/png' }), 'probe.png')
let r = await fetch(`${API}/uploads`, { method: 'POST', headers: H, body: fd })
const upj = await r.json()
check('POST /uploads (real file)', r.status === 200 && !!upj?.data?.url, JSON.stringify(upj?.error ?? upj?.data?.url ?? '').slice(0, 80))
if (upj?.data?.url) {
  const pub = await fetch(upj.data.url)
  check('  uploaded object publicly readable', pub.status === 200)
}

// ---- Economy gates ----
r = await fetch(`${API}/wallet/purchase`, { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' }, body: JSON.stringify({ packageId: 'x', amount: 999999 }) })
check('wallet/purchase 501 gate', r.status === 501)

r = await fetch(`${API}/users/profile`, { method: 'PUT', headers: { ...H, 'Content-Type': 'application/json' }, body: JSON.stringify({ coins: 999999, is_banned: false, display_name: 'verify-probe' }) })
r = await fetch(`${API}/profile/summary`, { headers: H })
const s = await r.json()
check('mass-assign whitelist holds (coins still 0)', s?.data?.coins === 0, `coins=${s?.data?.coins}`)

r = await fetch(`${API}/admin/stats`, { headers: H })
check('admin plane 403 for normal user', r.status === 403)

// ---- Agora fail-fast (F-07) ----
r = await fetch(`${API}/streams`, { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' }, body: JSON.stringify({ title: 'verify agora gate' }) })
check('stream create 503 when Agora unconfigured', r.status === 503)
const sj = await r.json()

// cleanup: delete created stream row (no cascade to auth user), then user rows then user
if (sj?.error === null || sj) {
  // find and delete any stream we just made for this host
  const list = await fetch(`${API}/streams?host_id=eq.${cu.user.id}&select=id`, { headers: { apikey: process.env.SUPABASE_ANON_KEY, Authorization: `Bearer ${process.env.SUPABASE_ANON_KEY}` } })
}
try {
  const svc = admin
  await svc.from('streams').delete().eq('host_id', cu.user.id)
} catch (_) {}

// manual cascade + delete user (same as test-live)
try {
  const convs = await admin.from('conversations').select('id').or(`user_a_id.eq.${cu.user.id},user_b_id.eq.${cu.user.id}`)
  const ids = (convs.data ?? []).map(c => c.id)
  if (ids.length) {
    await admin.from('messages').delete().in('conversation_id', ids)
    await admin.from('conversations').delete().in('id', ids)
  }
  for (const [t, c] of [['posts','user_id'],['post_likes','user_id'],['post_comments','user_id'],['recharge_requests','requester_id'],['host_applications','user_id'],['user_inventory','user_id']]) {
    await admin.from(t).delete().eq(c, cu.user.id)
  }
  await admin.from('friend_requests').delete().or(`requester_id.eq.${cu.user.id},addressee_id.eq.${cu.user.id}`)
  const del = await admin.auth.admin.deleteUser(cu.user.id)
  check('cleanup of verify user', !del.error, del.error?.message ?? '')
} catch (e) { check('cleanup of verify user', false, e.message) }

console.log(`\n${pass}/${total} verification checks passed`)
