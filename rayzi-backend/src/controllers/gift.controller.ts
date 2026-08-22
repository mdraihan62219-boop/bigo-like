import { Response } from 'express'
import { supabase } from '../config/database'
import { GiftService } from '../services/gift.service'
import { success, error } from '../utils/response'
import { pageParam, limitParam } from '../utils/pagination'
import { AuthenticatedRequest } from '../types'

export class GiftController {
  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      const { data } = await supabase.from('gifts').select('*').eq('is_active', true).order('sort_order')
      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async send(req: AuthenticatedRequest, res: Response) {
    try {
      const tx = await GiftService.sendGift({
        senderId: req.user!.id,
        receiverId: req.body.receiver_id,
        streamId: req.body.stream_id ?? null,
        giftId: req.body.gift_id,
        quantity: Number(req.body.quantity ?? 1),
      })

      if (tx === null) return error(res, 404, 'Gift not found')
      return success(res, tx, 'Gift sent successfully')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async getTransactions(req: AuthenticatedRequest, res: Response) {
    try {
      const page = pageParam(req.query.page)
      const limit = limitParam(req.query.limit)
      const type = req.query.type === 'received' ? 'received' : 'sent'
      const column = type === 'sent' ? 'sender_id' : 'receiver_id'

      const { data, count } = await supabase
        .from('gift_transactions')
        .select('*, gifts(*), profiles!gift_transactions_receiver_id_fkey(*)', { count: 'exact' })
        .eq(column, req.user!.id)
        .order('created_at', { ascending: false })
        .range((page - 1) * limit, page * limit - 1)

      return success(res, data, undefined, { page, limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
