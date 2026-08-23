import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'
import { InboxService } from '../dist/services/inbox.service.js'

const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } })
const email = 'phm.live.check+' + Date.now().toString(36) + '@gmail.com'
const pw = 'Test-' + Date.now().toString(36) + '-Pass!'
await admin.auth.admin.createUser({ email, password: pw, email_confirm: true })
// get the new user id
const { data: list } = await admin.auth.admin.listUsers()
const me = list.users.find((u) => u.email === email)
console.log('me:', me.id)
const r = await InboxService.openConversation(me.id, '6c73ee0e-25f2-4307-82b9-6b893c2ed9a3')
console.log(JSON.stringify(r).slice(0, 300))
process.exit(0)
