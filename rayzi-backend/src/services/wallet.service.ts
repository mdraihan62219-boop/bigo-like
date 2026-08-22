import { supabase } from '../config/database'

export class WalletService {
  static async deductCoins(userId: string, amount: number, description: string, referenceId?: string | null) {
    const { data: profile } = await supabase.from('profiles').select('coins').eq('id', userId).single()
    if (!profile || profile.coins < amount) throw new Error('Insufficient coins')

    const { error } = await supabase.rpc('deduct_coins', {
      p_user_id: userId, p_amount: amount
    })

    if (error) throw error

    await supabase.from('wallet_transactions').insert({
      user_id: userId, type: 'gift_sent', amount: -amount,
      currency: 'coins', description, reference_id: referenceId
    })
  }

  static async addDiamonds(userId: string, amount: number, description: string, referenceId?: string | null) {
    const { error } = await supabase.rpc('add_diamonds', {
      p_user_id: userId, p_amount: amount
    })

    if (error) throw error

    await supabase.from('wallet_transactions').insert({
      user_id: userId, type: 'gift_received', amount,
      currency: 'diamonds', description, reference_id: referenceId
    })
  }
}