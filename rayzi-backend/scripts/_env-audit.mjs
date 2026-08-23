import 'dotenv/config'
const check = (name, val) => {
  if (!val) return console.log(`${name}: MISSING`)
  const placeholder = /your-|xxx|placeholder|changeme|example/i.test(val)
  const looksReal = !placeholder && val.length >= 8
  console.log(`${name}: ${placeholder ? 'PLACEHOLDER' : looksReal ? 'SET (real-looking)' : 'SET (suspiciously short)'}`)
}
check('SUPABASE_URL', process.env.SUPABASE_URL)
check('SUPABASE_SERVICE_ROLE_KEY', process.env.SUPABASE_SERVICE_ROLE_KEY)
check('SUPABASE_ANON_KEY', process.env.SUPABASE_ANON_KEY)
check('JWT_SECRET', process.env.JWT_SECRET)
check('AGORA_APP_ID', process.env.AGORA_APP_ID)
check('AGORA_APP_CERTIFICATE', process.env.AGORA_APP_CERTIFICATE)
check('CORS_ORIGIN', process.env.CORS_ORIGIN)
check('REDIS_HOST', process.env.REDIS_HOST)
check('FIREBASE_PROJECT_ID', process.env.FIREBASE_PROJECT_ID)
// Cross-check supabase url matches the one baked in the Flutter app
const flutterUrl = 'https://yuokeoduqtxgfdlwuaaw.supabase.co'
console.log('SUPABASE_URL matches Flutter constants.dart:', process.env.SUPABASE_URL === flutterUrl)
