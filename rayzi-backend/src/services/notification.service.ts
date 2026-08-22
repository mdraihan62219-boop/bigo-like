import { supabase } from '../config/database'
import { messaging } from '../config/firebase'
import { logger } from '../utils/logger'

export class NotificationService {
  static async create(userId: string, type: string, title: string, body: string, data: any = {}) {
    const { error } = await supabase.from('notifications').insert({
      user_id: userId, type, title, body, data
    })
    if (error) logger.error('Failed to create notification', error)
  }

  static async sendPush(userId: string, title: string, body: string, data: any = {}) {
    if (!messaging) {
      logger.warn('Push skipped - Firebase not configured')
      return
    }
    try {
      const { data: tokens } = await supabase
        .from('push_tokens')
        .select('token')
        .eq('user_id', userId)

      if (!tokens?.length) return

      const messages = tokens.map((t: any) => ({
        token: t.token,
        notification: { title, body },
        data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)]))
      }))

      await messaging.sendEach(messages)
    } catch (err) {
      logger.error('Push notification failed', err)
    }
  }

  static async broadcastToFollowers(userId: string, title: string, body: string, data: any = {}) {
    const { data: followers } = await supabase
      .from('follows')
      .select('follower_id')
      .eq('following_id', userId)

    if (!followers) return

    for (const f of followers) {
      await this.create(f.follower_id, 'stream_start', title, body, data)
    }
  }
}