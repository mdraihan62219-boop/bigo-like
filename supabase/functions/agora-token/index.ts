import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { RtcTokenBuilder, RtcRole } from 'https://esm.sh/agora-token@2.0.3'

serve(async (req) => {
  const { channel_name, uid, role } = await req.json()
  const appId = Deno.env.get('AGORA_APP_ID')!
  const appCertificate = Deno.env.get('AGORA_APP_CERTIFICATE')!

  const expirationTimeInSeconds = 3600
  const currentTimestamp = Math.floor(Date.now() / 1000)
  const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds

  const token = RtcTokenBuilder.buildTokenWithUid(
    appId, appCertificate, channel_name, uid,
    role === 'host' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER,
    privilegeExpiredTs
  )

  return new Response(JSON.stringify({ token, expires_at: privilegeExpiredTs }), {
    headers: { 'Content-Type': 'application/json' }
  })
})