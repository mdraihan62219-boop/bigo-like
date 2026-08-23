import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'
import jwt from 'jsonwebtoken'

const BASE = 'https://bigo-like-1.onrender.com'
const API = `${BASE}/api/v1`
const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } })

async function req(method, path, body, headers = {}) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  let j = null
  try { j = await res.json() } catch (_) {}
  return { status: res.status, json: j }
}

// fresh confirmed user → real login
const email = `phm.audit+${Date.now().toString(36)}@gmail.com`
const pw = `Audit-${Date.now().toString(36)}-x!`
await admin.auth.admin.createUser({ email, password: pw, email_confirm: true })
const login = await req('POST', '/auth/login', { email, password: pw })
const realToken = login.json?.data?.token
console.log('real token obtained:', !!realToken)

// forge tokens with WRONG secret (simulates stale secret after rotation)
const wrongSecretToken = jwt.sign({ id: '6c73ee0e-25f2-4307-82b9-6b893c2ed9a3' }, 'definitely-wrong-secret-123', { expiresIn: '7d' })
// expired token signed with wrong secret too (can't sign with real one)
const H = (t) => ({ Authorization: `Bearer ${t}` })

const probes = [
  ['GET /rooms — NO token', () => req('GET', '/rooms')],
  ['GET /rooms — GARBAGE token', () => req('GET', '/rooms', undefined, H('not-a-jwt'))],
  ['GET /rooms — WRONG-SECRET signature', () => req('GET', '/rooms', undefined, H(wrongSecretToken))],
  ['GET /notifications — NO token', () => req('GET', '/notifications')],
  ['GET /notifications — WRONG-SECRET signature', () => req('GET', '/notifications', undefined, H(wrongSecretToken))],
  ['POST /streams (go live) — NO token', () => req('POST', '/streams', { title: 'audit probe' })],
  ['POST /streams (go live) — WRONG-SECRET signature', () => req('POST', '/streams', { title: 'audit probe' }, H(wrongSecretToken))],
  ['POST /streams (go live) — REAL token', () => req('POST', '/streams', { title: 'audit probe stream' }, H(realToken))],
  ['GET /rooms — REAL token', () => req('GET', '/rooms', undefined, H(realToken))],
  ['GET /notifications — REAL token', () => req('GET', '/notifications', undefined, H(realToken))],
]

for (const [name, fn] of probes) {
  const r = await fn()
  console.log(`${r.status}  ${name}  → ${JSON.stringify(r.json)?.slice(0, 140)}`)
}

// Agora token endpoint probes
const created = await req('POST', '/streams', { title: 'audit agora stream' }, H(realToken))
const streamId = created.json?.data?.id ?? created.json?.data?.stream?.id
console.log('\ncreated probe stream:', streamId ?? JSON.stringify(created.json).slice(0, 200))
if (streamId) {
  const tok = await req('GET', `/streams/${streamId}/token`, undefined, H(realToken))
  console.log(`GET /streams/:id/token → ${tok.status} ${JSON.stringify(tok.json)?.slice(0, 220)}`)
}
process.exit(0)
