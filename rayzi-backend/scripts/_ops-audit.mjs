import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'
const svc = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } })
const { data: buckets } = await svc.storage.listBuckets()
console.log('buckets:', buckets?.map(b => `${b.name}(${b.public ? 'public' : 'private'})`).join(', '))

// wallet purchase gate still 501?
const email = `phm.audit2+${Date.now().toString(36)}@gmail.com`
const pw = `Audit-${Date.now().toString(36)}-x!`
await svc.auth.admin.createUser({ email, password: pw, email_confirm: true })
const login = await fetch('https://bigo-like-1.onrender.com/api/v1/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pw }) })
const token = (await login.json())?.data?.token
const H = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }

let r = await fetch('https://bigo-like-1.onrender.com/api/v1/wallet/purchase', { method: 'POST', headers: H, body: JSON.stringify({ packageId: 'x', amount: 999999 }) })
console.log('wallet/purchase:', r.status, JSON.stringify(await r.json()).slice(0, 100))

// admin plane as non-admin (expect 403)
r = await fetch('https://bigo-like-1.onrender.com/api/v1/admin/stats', { headers: H })
console.log('admin/stats as user:', r.status, JSON.stringify(await r.json()).slice(0, 80))

// mass assignment probe: updateProfile with coins field should be whitelisted away
r = await fetch('https://bigo-like-1.onrender.com/api/v1/users/profile', { method: 'PUT', headers: H, body: JSON.stringify({ coins: 999999, is_banned: false, display_name: 'audit-probe-name' }) })
console.log('PUT users/profile mass-assign:', r.status, JSON.stringify(await r.json()).slice(0, 120))
// verify coins unchanged in profile summary
r = await fetch('https://bigo-like-1.onrender.com/api/v1/profile/summary', { headers: H })
const s = await r.json()
console.log('coins after mass-assign attempt:', s?.data?.coins, '(expect 0)')
