import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const { user_id, title, body, data } = await req.json()

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // Store notification in database
  const { error: dbError } = await supabase.from('notifications').insert({
    user_id,
    type: data?.type || 'system',
    title,
    body,
    data: data || {}
  })

  if (dbError) {
    return new Response(JSON.stringify({ error: dbError.message }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Get push tokens for the user
  const { data: tokens } = await supabase
    .from('push_tokens')
    .select('token')
    .eq('user_id', user_id)

  return new Response(JSON.stringify({
    success: true,
    stored: true,
    push_targets: tokens?.length || 0
  }), {
    headers: { 'Content-Type': 'application/json' }
  })
})