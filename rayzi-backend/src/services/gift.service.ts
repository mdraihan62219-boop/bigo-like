import { supabase } from '../config/database'
import { WalletService } from './wallet.service'

export interface SendGiftInput {
  senderId: string
  receiverId: string
  streamId?: string | null
  giftId: string
  quantity: number
}

/**
 * Single source of truth for the gift money-flow, shared by the REST route
 * and the Socket.IO handler so the economy cannot be bypassed through either
 * surface.
 *
 * Flow: deduct sender → credit receiver → record transaction, with
 * compensating refunds if any later step fails.
 *
 * @returns the inserted transaction row, or `null` when the gift does not
 *          exist / is inactive.
 * @throws Error with a user-safe message on validation or wallet failure.
 */
export class GiftService {
  static async sendGift(input: SendGiftInput) {
    const { senderId, receiverId, giftId } = input
    const quantity = input.quantity

    if (
      typeof giftId !== 'string' || !giftId ||
      typeof receiverId !== 'string' || !receiverId ||
      (input.streamId !== undefined && input.streamId !== null && typeof input.streamId !== 'string')
    ) {
      throw new Error('stream_id, gift_id and receiver_id are required')
    }
    if (!Number.isInteger(quantity) || quantity <= 0 || quantity > 1000) {
      throw new Error('quantity must be an integer between 1 and 1000')
    }
    if (receiverId === senderId) {
      throw new Error('Cannot send gifts to yourself')
    }

    const { data: gift } = await supabase.from('gifts')
      .select('*').eq('id', giftId).eq('is_active', true).single()
    if (!gift) return null

    const totalCoins = gift.price_coins * quantity
    const totalDiamonds = gift.diamond_value * quantity
    const streamRef = input.streamId ?? null

    await WalletService.deductCoins(senderId, totalCoins, `Sent ${gift.name} x${quantity}`, streamRef)

    try {
      await WalletService.addDiamonds(receiverId, totalDiamonds, `Received ${gift.name} x${quantity}`, streamRef)
    } catch (creditErr) {
      await supabase.rpc('add_coins', { p_user_id: senderId, p_amount: totalCoins })
      throw creditErr
    }

    try {
      const { data: tx, error: txError } = await supabase.from('gift_transactions').insert({
        sender_id: senderId, receiver_id: receiverId,
        stream_id: streamRef, gift_id: giftId,
        quantity, total_coins: totalCoins, total_diamonds: totalDiamonds
      }).select().single()

      if (txError) throw txError
      return tx ?? null
    } catch (txErr) {
      await supabase.rpc('add_coins', { p_user_id: senderId, p_amount: totalCoins })
      await supabase.rpc('deduct_diamonds', { p_user_id: receiverId, p_amount: totalDiamonds })
      throw txErr as Error
    }
  }
}
