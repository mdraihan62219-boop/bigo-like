import 'dotenv/config'
const r = await fetch(process.env.SUPABASE_URL + '/rest/v1/', {
  headers: { apikey: process.env.SUPABASE_ANON_KEY, Authorization: `Bearer ${process.env.SUPABASE_ANON_KEY}`, Accept: 'application/openapi+json' },
})
const spec = await r.json()
for (const t of ['conversations', 'messages', 'posts', 'shop_items']) {
  const def = spec.definitions?.[t]
  if (!def) { console.log('==', t, 'MISSING'); continue }
  console.log('==', t)
  console.log('   columns:', Object.keys(def.properties || {}).join(','))
}
