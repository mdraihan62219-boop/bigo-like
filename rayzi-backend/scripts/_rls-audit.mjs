import 'dotenv/config'
const ANON = { apikey: process.env.SUPABASE_ANON_KEY, Authorization: `Bearer ${process.env.SUPABASE_ANON_KEY}`, 'Content-Type': 'application/json' }
const base = process.env.SUPABASE_URL + '/rest/v1'
const DFG = '6c73ee0e-25f2-4307-82b9-6b893c2ed9a3'

async function probe(label, path, method, body) {
  const res = await fetch(`${base}/${path}`, { method, headers: ANON, body: body ? JSON.stringify(body) : undefined })
  const txt = res.status === 204 ? '(no content)' : await res.text().catch(() => '')
  console.log(`${res.status}  ${label} ${res.status >= 300 ? '— ' + txt.slice(0, 100) : ''}`)
}

// Same-value write to a REAL profile row: if RLS works → denied; if 204 → CRITICAL RLS gap
await probe('anon PATCH profiles/dfg same-value', `profiles?id=eq.${DFG}`, 'PATCH', { bio: '' })
// anon insert into posts (has insert policy) — expect deny
await probe('anon insert posts (expect deny)', 'posts', 'POST', { user_id: DFG, content: 'anon-probe' })
// anon read another user's inventory rows — expect [] (200 with zero rows is fine)
const r = await fetch(`${base}/user_inventory?select=id&user_id=eq.${DFG}`, { headers: ANON })
console.log(`${r.status}  anon read dfg inventory — rows: ${await r.text()}`)
// service-role sanity: same same-value patch SHOULD succeed (bypass)
const svc = { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' }
const r2 = await fetch(`${base}/profiles?id=eq.${DFG}`, { method: 'PATCH', headers: svc, body: JSON.stringify({ bio: '' }) })
console.log(`${r2.status}  service PATCH profiles/dfg same-value (expect 200/204)`)
