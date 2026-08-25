import { supabase } from '../config/database'

export class ResellerService {
  static async createRequest(userId: string, body: Record<string, unknown>) {
    const diamonds = Number(body.diamonds_requested)
    if (!Number.isInteger(diamonds) || diamonds <= 0 || diamonds > 1_000_000) {
      throw new Error('diamonds_requested must be a positive integer')
    }
    // The client may pass a shareable reseller_code (preferred) — resolve it
    // server-side to an active agent. A raw reseller_id is still accepted
    // for backwards compatibility but is validated the same way.
    let resellerId: string | null = null
    const code = typeof body.reseller_code === 'string' && body.reseller_code.trim()
      ? body.reseller_code.trim().toUpperCase() : ''
    if (code) {
      const { data: agent, error: codeErr } = await supabase
        .from('reseller_agents').select('id').eq('reseller_code', code).eq('is_active', true)
        .maybeSingle()
      if (codeErr) throw new Error(codeErr.message)
      if (!agent) throw new Error(`No active reseller found with code ${code}`)
      resellerId = (agent as { id: string }).id
    } else if (typeof body.reseller_id === 'string' && body.reseller_id) {
      resellerId = body.reseller_id
    }
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
      .from('recharge_requests').select('*, reseller_agents(reseller_code)').eq('requester_id', userId)
      .order('created_at', { ascending: false })
    if (error) throw new Error(error.message)
    return data
  }

  static async adminListRequests(status?: string) {
    let query = supabase.from('recharge_requests')
      .select('*, reseller_agents(reseller_code), profiles!recharge_requests_requester_id_fkey(username, display_name)')
      .order('created_at', { ascending: true })
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

  /**
   * Reseller Dashboard payload. Returns `agent: null` when the caller has
   * no active reseller_agents row (the app uses that to hide/gate the UI).
   * Pending requests are scoped to the caller's own agent id, and ledger
   * activity is scoped to the caller's own credit pool.
   */
  static async dashboard(userId: string) {
    const { data: agent, error: agentErr } = await supabase
      .from('reseller_agents')
      .select('*')
      .eq('user_id', userId)
      .eq('is_active', true)
      .maybeSingle()
    if (agentErr) throw new Error(agentErr.message)
    if (!agent) return { agent: null, pending_requests: [], recent_ledger: [] }

    const [pendingRes, ledgerRes] = await Promise.all([
      supabase
        .from('recharge_requests')
        .select('*, profiles!recharge_requests_requester_id_fkey(username, display_name)')
        .eq('reseller_id', (agent as { id: string }).id)
        .eq('status', 'pending')
        .order('created_at', { ascending: true }),
      supabase
        .from('wallet_ledger')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(30),
    ])
    if (pendingRes.error) throw new Error(pendingRes.error.message)
    if (ledgerRes.error) throw new Error(ledgerRes.error.message)

    return {
      agent,
      pending_requests: pendingRes.data ?? [],
      recent_ledger: ledgerRes.data ?? [],
    }
  }

  /**
   * Scoped approve/reject for DASHBOARD callers. The RPC itself enforces:
   * full admins pass unrestricted; a reseller-role caller may only touch
   * requests whose reseller_id equals their own reseller_agents.id.
   */
  static async approveScoped(requestId: string, callerId: string) {
    const { error } = await supabase.rpc('approve_recharge_request', {
      p_request_id: requestId, p_actor: callerId,
    })
    if (error) return { ok: false as const, message: error.message }
    return { ok: true as const }
  }

  static async rejectScoped(requestId: string, callerId: string, reason: string) {
    const { error } = await supabase.rpc('reject_recharge_request', {
      p_request_id: requestId, p_actor: callerId, p_reason: reason,
    })
    if (error) return { ok: false as const, message: error.message }
    return { ok: true as const }
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
