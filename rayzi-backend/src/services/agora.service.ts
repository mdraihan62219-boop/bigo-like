import { RtcTokenBuilder, RtcRole } from 'agora-token'

const appId = process.env.AGORA_APP_ID!
const appCertificate = process.env.AGORA_APP_CERTIFICATE!

/**
 * True when both credentials look real. Placeholders (or empties) make
 * agora-token silently return "" tokens — we refuse to mint those and
 * fail fast with 503 instead of handing clients garbage.
 */
export function isAgoraConfigured(): boolean {
  return Boolean(appId) && Boolean(appCertificate)
    && !/your-|placeholder|xxx|changeme/i.test(appId)
    && !/your-|placeholder|xxx|changeme/i.test(appCertificate)
}

export class AgoraService {
  static generateToken(channelName: string, uid: number, role: 'host' | 'audience', expireHours = 24) {
    if (!isAgoraConfigured()) {
      throw new AgoraNotConfiguredError()
    }
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

export class AgoraNotConfiguredError extends Error {
  constructor() {
    super('Agora not configured')
    this.name = 'AgoraNotConfiguredError'
  }
}
