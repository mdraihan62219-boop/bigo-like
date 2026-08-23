import { supabase } from '../config/database'

const CONV_SELECT = `*, user_a:profiles!conversations_user_a_id_fkey(id, username, display_name, avatar_url), user_b:profiles!conversations_user_b_id_fkey(id, username, display_name, avatar_url)`

export class InboxService {
  /** Finds or creates the conversation between two users (ordered pair). */
  static async openConversation(userId: string, otherUserId: string) {
    if (userId === otherUserId) throw new Error('Cannot open a conversation with yourself')
    const { data: other } = await supabase.from('profiles').select('id').eq('id', otherUserId).single()
    if (!other) return { ok: false as const, status: 404, message: 'User not found' }

    const [a, b] = [userId, otherUserId].sort()
    let { data: conv } = await supabase.from('conversations')
      .select(CONV_SELECT).eq('user_a_id', a).eq('user_b_id', b).maybeSingle()

    if (!conv) {
      const { data: created, error } = await supabase.from('conversations')
        .insert({ user_a_id: a, user_b_id: b }).select(CONV_SELECT).single()
      if (error) throw new Error(error.message)
      conv = created
    }
    return { ok: true as const, status: 200, data: conv }
  }

  static isParticipant(conv: { user_a_id: string; user_b_id: string }, userId: string) {
    return conv.user_a_id === userId || conv.user_b_id === userId
  }

  static async listConversations(userId: string) {
    const { data, error } = await supabase.from('conversations')
      .select(CONV_SELECT).or(`user_a_id.eq.${userId},user_b_id.eq.${userId}`)
      .order('last_message_at', { ascending: false })
    if (error) throw new Error(error.message)
    return data ?? []
  }

  static async getConversation(userId: string, conversationId: string) {
    const { data: conv, error } = await supabase.from('conversations')
      .select(CONV_SELECT).eq('id', conversationId).maybeSingle()
    if (error) throw new Error(error.message)
    if (!conv || !this.isParticipant(conv, userId)) return null
    return conv
  }

  static async listMessages(conversationId: string, page: number, limit: number) {
    const { data, error } = await supabase.from('messages')
      .select('*, sender:profiles!messages_sender_id_fkey(id, username, display_name, avatar_url)')
      .eq('conversation_id', conversationId).order('created_at', { ascending: false })
      .range((page - 1) * limit, page * limit - 1)
    if (error) throw new Error(error.message)
    return (data ?? []).reverse() // oldest → newest for chat rendering
  }

  /**
   * Sends a message. The 60-second reel cap is enforced by the DB CHECK
   * constraint as well — this is the client-side guard.
   */
  static async sendMessage(userId: string, conversationId: string, body: Record<string, unknown>) {
    const type = body.message_type
    if (!['text', 'photo', 'video_reel', 'call_log'].includes(type as string)) {
      throw new Error('Invalid message_type')
    }
    const row: Record<string, unknown> = {
      conversation_id: conversationId, sender_id: userId, message_type: type,
    }
    if (type === 'text') {
      const text = typeof body.text_content === 'string' ? body.text_content.trim().slice(0, 2000) : ''
      if (!text) throw new Error('Message cannot be empty')
      row.text_content = text
    } else if (type === 'photo' || type === 'video_reel') {
      const url = typeof body.media_url === 'string' ? body.media_url.slice(0, 1000) : ''
      if (!url) throw new Error('media_url required')
      row.media_url = url
      if (type === 'video_reel') {
        const dur = Number(body.media_duration_seconds)
        if (!Number.isInteger(dur) || dur <= 0 || dur > 60) {
          throw new Error('Reel messages are limited to 60 seconds')
        }
        row.media_duration_seconds = dur
      }
    } else if (type === 'call_log') {
      const callType = body.call_type === 'video' ? 'video' : 'audio'
      const dur = Number(body.call_duration_seconds ?? 0)
      row.call_type = callType
      row.call_duration_seconds = Number.isInteger(dur) && dur >= 0 ? dur : 0
    }

    const { data, error } = await supabase.from('messages').insert(row)
      .select('*, sender:profiles!messages_sender_id_fkey(id, username, display_name, avatar_url)').single()
    if (error) throw new Error(error.message)

    await supabase.from('conversations').update({ last_message_at: new Date().toISOString() }).eq('id', conversationId)
    return data
  }

  static async markRead(conversationId: string, userId: string) {
    const { error } = await supabase.from('messages')
      .update({ is_read: true }).eq('conversation_id', conversationId).neq('sender_id', userId)
    if (error) throw new Error(error.message)
    return 'Read'
  }
}
