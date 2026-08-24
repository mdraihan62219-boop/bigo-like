import { supabase } from '../config/database'

const isPositiveInt = (v: unknown): v is number =>
  typeof v === 'number' && Number.isInteger(v) && v > 0

const VALID_METHODS = ['bkash', 'nagad', 'bank_transfer', 'other']

/**
 * Withdraw flow: submit debits (holds) the diamonds immediately via an
 * atomic RPC so a pending withdrawal cannot be double-spent. Admin reject
 * reverses the hold; admin mark-paid confirms an external manual payout.
 * No real-money transfer happens in-process — payout is sent manually by
 * the operator and then recorded here.
 */
export class WithdrawService {
  static async submit(userId: string, body: Record<string, unknown>) {
    const diamonds = body.diamonds_requested ?? body.amount
    if (!isPositiveInt(Number(diamonds)) || Number(diamonds) > 10_000_000) {
      throw new Error('diamonds_requested must be a positive integer')
    }
    const method = typeof body.payout_method === 'string' ? body.payout_method : ''
    if (!VALID_METHODS.includes(method)) {
      throw new Error(`payout_method must be one of ${VALID_METHODS.join(', ')}`)
    }
    const details = body.payout_details
    if (details === null || details === undefined || typeof details !== 'object' || Array.isArray(details)) {
      throw new Error('payout_details object required (account number / name)')
    }
    // Cap free-form strings inside details.
    const safeDetails: Record<string, unknown> = {}
    for (const [k, v] of Object.entries(details as Record<string, unknown>).slice(0, 20)) {
      safeDetails[k.slice(0, 40)] = typeof v === 'string' ? v.slice(0, 200) : v
    }

    const { data, error } = await supabase.rpc('create_withdraw_request', {
      p_user_id: userId,
      p_diamonds: Number(diamonds),
      p_method: method,
      p_details: safeDetails,
    })
    if (error) throw new Error(error.message)
    return data
  }

  /** The user's own withdrawal history. */
  static async mine(userId: string) {
    const { data, error } = await supabase
      .from('withdraw_requests')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(100)
    if (error) throw new Error(error.message)
    return data ?? []
  }

  /** Admin queue. */
  static async adminList(status?: string) {
    let query = supabase
      .from('withdraw_requests')
      .select('*, profiles!withdraw_requests_user_id_fkey(username, display_name)')
      .order('created_at', { ascending: true })
      .limit(200)
    if (status) query = query.eq('status', status)
    const { data, error } = await query
    if (error) throw new Error(error.message)
    return data ?? []
  }

  static async adminApprove(requestId: string, adminId: string) {
    const { error } = await supabase.rpc('admin_approve_withdraw', {
      p_request_id: requestId, p_admin: adminId,
    })
    if (error) return { ok: false as const, message: error.message }
    return { ok: true as const }
  }

  static async adminMarkPaid(requestId: string, adminId: string) {
    const { error } = await supabase.rpc('admin_mark_withdraw_paid', {
      p_request_id: requestId, p_admin: adminId,
    })
    if (error) return { ok: false as const, message: error.message }
    return { ok: true as const }
  }

  static async adminReject(requestId: string, adminId: string, reason: string) {
    const { error } = await supabase.rpc('admin_reject_withdraw', {
      p_request_id: requestId, p_admin: adminId, p_reason: reason,
    })
    if (error) return { ok: false as const, message: error.message }
    return { ok: true as const }
  }
}
