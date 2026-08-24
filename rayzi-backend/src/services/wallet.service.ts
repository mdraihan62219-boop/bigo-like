import { supabase } from '../config/database'

/**
 * WalletService — every mutation goes through an atomic Postgres RPC that
 * updates the balance AND appends a wallet_ledger row in the same
 * transaction. The service layer only validates shape and passes audit
 * metadata (reason / actor / reference) through.
 */
export class WalletService {
  static async deductCoins(
    userId: string,
    amount: number,
    description: string,
    referenceId?: string | null,
    reason = 'gift_sent',
    actorId?: string | null,
  ) {
    const { error } = await supabase.rpc('deduct_coins', {
      p_user_id: userId,
      p_amount: amount,
      p_reason: reason,
      p_actor_type: 'user',
      p_actor_id: actorId ?? userId,
      p_reference_id: referenceId ?? null,
      p_note: description,
    })
    if (error) throw new Error(error.message)
  }

  static async addDiamonds(
    userId: string,
    amount: number,
    description: string,
    referenceId?: string | null,
    reason = 'gift_received',
    actorId?: string | null,
  ) {
    const { error } = await supabase.rpc('add_diamonds', {
      p_user_id: userId,
      p_amount: amount,
      p_reason: reason,
      p_actor_type: 'user',
      p_actor_id: actorId ?? userId,
      p_reference_id: referenceId ?? null,
      p_note: description,
    })
    if (error) throw new Error(error.message)
  }

  /** Own ledger history (new wallet_ledger table). */
  static async getLedger(userId: string, page: number, limit: number, reason?: string) {
    let query = supabase
      .from('wallet_ledger')
      .select('*', { count: 'exact' })
      .eq('user_id', userId)
    if (reason) query = query.eq('reason', reason)
    const { data, error, count } = await query
      .order('created_at', { ascending: false })
      .range((page - 1) * limit, page * limit - 1)
    if (error) throw new Error(error.message)
    return { rows: data ?? [], total: count ?? 0 }
  }

  /** Active resellers for the Buy-Coins screen — shareable codes only. */
  static async listActiveResellers() {
    const { data, error } = await supabase.rpc('list_active_resellers')
    if (error) throw new Error(error.message)
    return data ?? []
  }
}
