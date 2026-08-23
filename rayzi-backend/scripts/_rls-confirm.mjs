import 'dotenv/config'
const ANON = { apikey: process.env.SUPABASE_ANON_KEY, Authorization: `Bearer ${process.env.SUPABASE_ANON_KEY}`, 'Content-Type': 'application/json' }
const SVC = { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' }
const base = process.env.SUPABASE_URL + '/rest/v1'
const DFG = '6c73ee0e-25f2-4307-82b9-6b893c2ed9a3'

// capture current bio
let r = await fetch(`${base}/profiles?select=bio&id=eq.${DFG}`, { headers: ANON })
const before = await r.json()
console.log('bio before:', JSON.stringify(before))

// attempt anon write of a marker
r = await fetch(`${base}/profiles?id=eq.${DFG}`, { method: 'PATCH', headers: ANON, body: JSON.stringify({ bio: '__AUDIT_MARKER__' }) })
console.log('anon PATCH status:', r.status)

// check if it landed
r = await fetch(`${base}/profiles?select=bio&id=eq.${DFG}`, { headers: ANON })
const after = await r.json()
console.log('bio after:', JSON.stringify(after))

if (JSON.stringify(after).includes('AUDIT_MARKER')) {
  console.log('>>> CONFIRMED: ANONYMOUS WRITE TO PROFILES SUCCEEDED — CRITICAL RLS GAP')
  // restore original
  const orig = Array.isArray(before) ? before[0]?.bio ?? '' : before?.bio ?? ''
  const rr = await fetch(`${base}/profiles?id=eq.${DFG}`, { method: 'PATCH', headers: SVC, body: JSON.stringify({ bio: orig }) })
  console.log('restored original bio:', rr.status)
} else {
  console.log('>>> anon write did NOT land (RLS held); earlier 204s were zero-row-match artifacts')
}
