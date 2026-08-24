import { supabase } from '../config/database'
import { WalletService } from './wallet.service'
import { logger } from '../utils/logger'

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
      // Refund path — audited as reason 'other' with a refund note.
      const { error: refundError } = await supabase.rpc('add_coins', {
        p_user_id: senderId, p_amount: totalCoins,
        p_reason: 'other', p_actor_type: 'system',
        p_reference_id: streamRef, p_note: 'refund: receiver credit failed',
      })
      if (refundError) logger.error(`Gift refund failed for ${senderId}: ${refundError.message}`)
      throw creditErr
    }

    try {
      const { data: tx, error: txError } = await supabase.from('gift_transactions').insert({
        sender_id: senderId, receiver_id: receiverId,
        stream_id: streamRef, gift_id: giftId,
        quantity, total_coins: totalCoins, total_diamonds: totalDiamonds
      }).select().single()

      if (txError) throw txError

      // PK battle scoring — same write path as the gift economy (single source
      // of truth). No-op when the receiving stream is not in an active battle.
      let pkUpdate = null
      if (streamRef) {
        try {
          const { data } = await supabase.rpc('pk_apply_score', {
            p_stream_id: streamRef, p_amount: totalCoins,
          })
          pkUpdate = data ?? null
        } catch (pkErr) {
          // Battle scoring must never fail the gift itself.
        }
      }

      return { ...(tx ?? {}), pk_update: pkUpdate }
    } catch (txErr) {
      // Full compensating refund — both sides audited as 'other'/system.
      const { error: refundCoinsError } = await supabase.rpc('add_coins', {
        p_user_id: senderId, p_amount: totalCoins,
        p_reason: 'other', p_actor_type: 'system',
        p_reference_id: streamRef, p_note: 'refund: gift transaction failed',
      })
      if (refundCoinsError) logger.error(`Gift coin-refund failed for ${senderId}: ${refundCoinsError.message}`)
      if (totalDiamonds > 0) {
        const { error: refundDiamondsError } = await supabase.rpc('deduct_diamonds', {
          p_user_id: receiverId, p_amount: totalDiamonds,
          p_reason: 'other', p_actor_type: 'system',
          p_reference_id: streamRef, p_note: 'reverse-credit: gift transaction failed',
        })
        if (refundDiamondsError) logger.error(`Gift diamond-reversal failed for ${receiverId}: ${refundDiamondsError.message}`)
      }
      throw txErr as Error
    }
  }
}
