import { supabase } from '../config/database'

const FRIEND_SELECT = `*, requester:profiles!friend_requests_requester_id_fkey(id, username, display_name, avatar_url), addressee:profiles!friend_requests_addressee_id_fkey(id, username, display_name, avatar_url)`

export class FriendService {
  static async sendRequest(requesterId: string, addresseeId: string) {
    if (requesterId === addresseeId) throw new Error('Cannot friend yourself')
    const { data: target } = await supabase.from('profiles').select('id').eq('id', addresseeId).single()
    if (!target) return { ok: false as const, status: 404, message: 'User not found' }

    const { data: existing } = await supabase.from('friend_requests')
      .select('id,status,requester_id').or(`and(requester_id.eq.${requesterId},addressee_id.eq.${addresseeId}),and(requester_id.eq.${addresseeId},addressee_id.eq.${requesterId})`)
      .limit(1)
    if (existing?.length) {
      if (existing[0].status === 'pending') {
        // If the other side requested us first, this acts as an auto-accept.
        if (existing[0].requester_id === addresseeId) {
          await supabase.from('friend_requests').update({ status: 'accepted' }).eq('id', existing[0].id)
          return { ok: true as const, status: 200, message: 'Friend request accepted', data: { accepted: true } }
        }
        return { ok: false as const, status: 409, message: 'Request already pending' }
      }
      return { ok: false as const, status: 409, message: `Already ${existing[0].status}` }
    }

    const { data, error } = await supabase.from('friend_requests').insert({
      requester_id: requesterId, addressee_id: addresseeId,
    }).select(FRIEND_SELECT).single()
    if (error) throw new Error(error.message)
    return { ok: true as const, status: 201, message: 'Request sent', data }
  }

  static async respond(userId: string, requestId: string, accept: boolean) {
    const patch = { status: accept ? 'accepted' : 'rejected' }
    const { data, error } = await supabase
      .from('friend_requests').update(patch).eq('id', requestId).eq('addressee_id', userId)
      .eq('status', 'pending').select(FRIEND_SELECT).single()
    if (error || !data) return { ok: false as const, status: 404, message: 'Pending request not found' }
    return { ok: true as const, status: 200, data }
  }

  static async listFriends(userId: string) {
    const { data, error } = await supabase.from('friend_requests')
      .select(FRIEND_SELECT).eq('status', 'accepted')
      .or(`requester_id.eq.${userId},addressee_id.eq.${userId}`)
    if (error) throw new Error(error.message)
    const friends = (data ?? []).map((r: Record<string, unknown>) =>
      r.requester_id === userId ? r.addressee : r.requester)
    return friends
  }

  static async listRequests(userId: string) {
    const { data, error } = await supabase.from('friend_requests')
      .select(FRIEND_SELECT).eq('status', 'pending').eq('addressee_id', userId)
      .order('created_at', { ascending: false })
    if (error) throw new Error(error.message)
    return data ?? []
  }

  static async count(userId: string) {
    const { count, error } = await supabase.from('friend_requests')
      .select('*', { count: 'exact', head: true }).eq('status', 'accepted')
      .or(`requester_id.eq.${userId},addressee_id.eq.${userId}`)
    if (error) throw new Error(error.message)
    return count ?? 0
  }
}
