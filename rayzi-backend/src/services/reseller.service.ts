import { supabase } from '../config/database'

export class ResellerService {
  static async createRequest(userId: string, body: Record<string, unknown>) {
    const diamonds = Number(body.diamonds_requested)
    if (!Number.isInteger(diamonds) || diamonds <= 0 || diamonds > 1_000_000) {
      throw new Error('diamonds_requested must be a positive integer')
    }
    const resellerId = typeof body.reseller_id === 'string' && body.reseller_id ? body.reseller_id : null
    const proofUrl = typeof body.payment_proof_url === 'string' ? body.payment_proof_url.slice(0, 1000) : null

    const { data: active, error: activeErr } = await supabase
      .from('recharge_requests').select('id').eq('requester_id', userId).eq('status', 'pending').limit(1)
    if (activeErr) throw new Error(activeErr.message)
    if (active?.length) throw new Error('You already have a pending recharge request')

    const { data, error } = await supabase.from('recharge_requests').insert({
      requester_id: userId, reseller_id: resellerId,
      diamonds_requested: diamonds, payment_proof_url: proofUrl,
      note: typeof body.note === 'string' ? body.note.slice(0, 500) : null,
    }).select().single()
    if (error) throw new Error(error.message)
    return data
  }

  static async myRequests(userId: string) {
    const { data, error } = await supabase
      .from('recharge_requests').select('*').eq('requester_id', userId)
      .order('created_at', { ascending: false })
    if (error) throw new Error(error.message)
    return data
  }

  static async adminListRequests(status?: string) {
    let query = supabase.from('recharge_requests').select('*').order('created_at', { ascending: true })
    if (status) query = query.eq('status', status)
    const { data, error } = await query
    if (error) throw new Error(error.message)
    return data
  }

  /** Approval runs the atomic RPC — reseller debit + user credit in one transaction. */
  static async adminApprove(requestId: string, adminId: string) {
    const { error } = await supabase.rpc('approve_recharge_request', {
      p_request_id: requestId, p_admin: adminId,
    })
    if (error) return { ok: false as const, message: error.message }
    return { ok: true as const }
  }

  static async adminReject(requestId: string, adminId: string, reason: string) {
    const { data: req } = await supabase.from('recharge_requests')
      .select('status').eq('id', requestId).single()
    if (!req) return { ok: false as const, message: 'Request not found' }
    if (req.status !== 'pending') return { ok: false as const, message: 'Request already processed' }
    const { error } = await supabase.from('recharge_requests').update({
      status: 'rejected', processed_by: adminId, processed_at: new Date().toISOString(),
      rejection_reason: reason,
    }).eq('id', requestId)
    if (error) return { ok: false as const, message: error.message }
    return { ok: true as const }
  }

  // ---- agent management (admin) ----
  static async adminListAgents() {
    const { data, error } = await supabase
      .from('reseller_agents').select('*, profiles!reseller_agents_user_id_fkey(username, display_name)')
      .order('created_at', { ascending: false })
    if (error) throw new Error(error.message)
    return data
  }

  static async adminUpsertAgent(body: Record<string, unknown>) {
    const userId = typeof body.user_id === 'string' ? body.user_id : ''
    if (!userId) throw new Error('user_id required')
    const credit = Number(body.diamond_credit_balance ?? 0)
    if (!Number.isFinite(credit) || credit < 0) throw new Error('invalid diamond_credit_balance')
    const rate = body.commission_rate === undefined ? undefined : Number(body.commission_rate)

    const patch: Record<string, unknown> = { diamond_credit_balance: Math.floor(credit), is_active: body.is_active ?? true }
    if (rate !== undefined && Number.isFinite(rate)) patch.commission_rate = rate
    const { data, error } = await supabase.from('reseller_agents').upsert({ user_id: userId, ...patch }, { onConflict: 'user_id' }).select().single()
    if (error) throw new Error(error.message)
    return data
  }
}
