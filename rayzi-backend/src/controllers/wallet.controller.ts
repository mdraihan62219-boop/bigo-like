import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { pageParam, limitParam } from '../utils/pagination'
import { AuthenticatedRequest } from '../types'

const isPositiveInt = (v: unknown): v is number =>
  typeof v === 'number' && Number.isInteger(v) && v > 0

export class WalletController {
  static async getBalance(req: AuthenticatedRequest, res: Response) {
    try {
      const { data } = await supabase.from('profiles')
        .select('coins, diamonds')
        .eq('id', req.user!.id).single()
      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getTransactions(req: AuthenticatedRequest, res: Response) {
    try {
      const page = pageParam(req.query.page)
      const limit = limitParam(req.query.limit)
      const { currency, type } = req.query
      let query = supabase.from('wallet_transactions')
        .select('*', { count: 'exact' })
        .eq('user_id', req.user!.id)

      if (currency) query = query.eq('currency', currency)
      if (type) query = query.eq('type', type)

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((page - 1) * limit, page * limit - 1)

      return success(res, data, undefined, { page, limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  /**
   * DISABLED until a real payment provider (Stripe/Razorpay) with signed
   * webhooks exists. The previous implementation credited coins directly
   * from client-supplied amounts — an unlimited money printer.
   */
  static async purchaseCoins(_req: AuthenticatedRequest, res: Response) {
    return res.status(501).json({
      success: false,
      error: 'Coin purchases are not available yet. Payment integration pending.'
    })
  }

  static async withdrawDiamonds(req: AuthenticatedRequest, res: Response) {
    try {
      const amount = Number(req.body.amount)
      const payment_method = typeof req.body.payment_method === 'string' ? req.body.payment_method : ''
      const payment_details =
        typeof req.body.payment_details === 'string' ? req.body.payment_details.slice(0, 500) : ''

      if (!isPositiveInt(amount)) return error(res, 400, 'Invalid withdrawal amount')
      if (!payment_method) return error(res, 400, 'Payment method required')
      if (amount < 1000) return error(res, 400, 'Minimum withdrawal is 1000 diamonds')

      // deduct_diamonds RPC enforces the balance atomically server-side;
      // this pre-check only produces a friendlier error message.
      const { data: profile } = await supabase.from('profiles')
        .select('diamonds').eq('id', req.user!.id).single()

      if (!profile || profile.diamonds < amount) return error(res, 400, 'Insufficient diamonds')

      const { error: rpcError } = await supabase.rpc('deduct_diamonds', {
        p_user_id: req.user!.id, p_amount: amount
      })

      if (rpcError) return error(res, 400, rpcError.message)

      await supabase.from('wallet_transactions').insert({
        user_id: req.user!.id, type: 'withdrawal', amount: -amount,
        currency: 'diamonds',
        description: `Withdrawal via ${payment_method}${payment_details ? ` (${payment_details})` : ''}`,
        status: 'pending'
      })

      return success(res, { amount }, 'Withdrawal requested')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
