import { createClient, SupabaseClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.SUPABASE_URL!
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY!

/**
 * Service-role data client — BYPASSES RLS.
 *
 * NEVER call supabase.auth.signInWithPassword / signUp / signInWithIdToken on
 * this instance: supabase-js stores the resulting session and silently swaps
 * every later request's Authorization header to that user's token, breaking
 * service-role semantics (and cross-contaminating users on a shared server).
 * Use createAuthClient() for those flows instead.
 */
export const supabase: SupabaseClient = createClient(supabaseUrl, supabaseKey, {
  auth: { autoRefreshToken: false, persistSession: false }
})

/**
 * Fresh anonymous-scoped client per auth flow (login/register/social).
 * Session persistence is disabled; the caller only consumes the returned
 * user/session objects and discards the client.
 */
export function createAuthClient(): SupabaseClient {
  return createClient(supabaseUrl, process.env.SUPABASE_ANON_KEY ?? supabaseKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  })
}
