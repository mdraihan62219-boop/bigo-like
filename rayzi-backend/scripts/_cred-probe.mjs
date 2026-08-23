import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'
const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } })
const BASE = 'https://bigo-like-1.onrender.com'
const API = `${BASE}/api/v1`

const email = `phm.cred+${Date.now().toString(36)}@gmail.com`
const pw = `Cred-${Date.now().toString(36)}-x!`
await admin.auth.admin.createUser({ email, password: pw, email_confirm: true })
const login = await fetch(`${API}/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pw }) })
const token = (await login.json())?.data?.token
const H = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }

// ---- 1. AGORA: token endpoint must now return a NON-EMPTY token ----
const cs = await fetch(`${API}/streams`, { method: 'POST', headers: H, body: JSON.stringify({ title: '[CRED-PROBE] agora stream' }) })
const csj = await cs.json()
console.log(`stream create: ${cs.status} ${csj?.error ?? ''}`)
if (csj?.data?.id) {
  const tk = await fetch(`${API}/streams/${csj.data.id}/token`, { headers: H })
  const tj = await tk.json()
  const tok = tj?.data?.token ?? ''
  console.log(`token endpoint: ${tk.status}, token length: ${tok.length}`)
  console.log(tok.length > 50 ? 'AGORA: ✅ REAL TOKEN ISSUED' : 'AGORA: ❌ still broken')
}

// ---- 2. GOOGLE PROVIDER: fake-token probe; error text tells us provider state ----
const soc = await fetch(`${API}/auth/social`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ provider: 'google', token: 'not-a-real-id-token' }) })
const sj = await soc.json()
console.log(`social probe: ${soc.status} ${JSON.stringify(sj)}`)
const msg = String(sj?.error ?? '')
if (/not enabled/i.test(msg)) console.log('GOOGLE: ❌ provider still disabled in Supabase')
else if (/invalid|token|audience|signature|client/i.test(msg)) console.log('GOOGLE: ✅ provider ENABLED (rejecting the fake token as expected)')
else console.log('GOOGLE: ⚠️ unexpected response')

// cleanup this user
await admin.from('streams').delete().eq('host_id', (await admin.from('profiles').select('id').eq('username', (await admin.auth.admin.listUsers()).data.users.find(u => u.email === email).user_metadata?.username ?? '').maybeSingle()).data?.id)
process.exit(0)
