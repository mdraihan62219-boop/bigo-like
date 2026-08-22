import { RtcTokenBuilder, RtcRole } from 'agora-token'

const appId = process.env.AGORA_APP_ID!
const appCertificate = process.env.AGORA_APP_CERTIFICATE!

export class AgoraService {
  static generateToken(channelName: string, uid: number, role: 'host' | 'audience', expireHours = 24) {
    const expirationTimeInSeconds = expireHours * 3600
    const currentTimestamp = Math.floor(Date.now() / 1000)
    const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds
    const rtcRole = role === 'host' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER

    return RtcTokenBuilder.buildTokenWithUid(
      appId, appCertificate, channelName, uid, rtcRole,
      expirationTimeInSeconds, privilegeExpiredTs
    )
  }

  static generateChannelName(userId: string): string {
    return `stream_${userId}_${Date.now()}`
  }
}