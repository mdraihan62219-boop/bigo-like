import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'
const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } })
const email = 'phm.live.check+' + Date.now().toString(36) + '@gmail.com'
const pw = 'Test-' + Date.now().toString(36) + '-Pass!'
const { data: cu, error: ce } = await admin.auth.admin.createUser({ email, password: pw, email_confirm: true })
console.log('createUser:', ce?.message ?? 'ok')
const r = await fetch('https://bigo-like-1.onrender.com/api/v1/auth/login', {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, password: pw }),
})
const lj = await r.json()
console.log('login:', lj?.success, lj?.error ?? '')
const token = lj?.data?.token
const other = '6c73ee0e-25f2-4307-82b9-6b893c2ed9a3'
const r2 = await fetch(`https://bigo-like-1.onrender.com/api/v1/inbox/conversations/open/${other}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
})
console.log('open conv:', r2.status, JSON.stringify(await r2.json()))
