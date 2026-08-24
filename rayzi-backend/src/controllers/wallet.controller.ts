import { Response } from 'express'
import { supabase } from '../config/database'
import { success, created, error } from '../utils/response'
import { pageParam, limitParam } from '../utils/pagination'
import { AuthenticatedRequest } from '../types'
import { WalletService } from '../services/wallet.service'
import { WithdrawService } from '../services/withdraw.service'
import { ResellerService } from '../services/reseller.service'

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

  /** Audit-grade ledger (wallet_ledger) for the signed-in user. */
  static async getLedger(req: AuthenticatedRequest, res: Response) {
    try {
      const page = pageParam(req.query.page)
      const limit = Math.min(limitParam(req.query.limit), 100)
      const reason = typeof req.query.reason === 'string' ? req.query.reason : undefined
      const result = await WalletService.getLedger(req.user!.id, page, limit, reason)
      return success(res, result.rows, undefined, { page, limit, total: result.total })
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

  // -------------------------------------------------------------------
  // Buy coins from a reseller (professional flow)
  // -------------------------------------------------------------------

  /** Directory of active resellers — shareable codes only, no raw ids. */
  static async listResellers(_req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await WalletService.listActiveResellers())
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  /**
   * Submit a recharge request against a reseller CODE. The code is resolved
   * server-side to an active agent — a client-supplied raw agent id is never
   * trusted. Balance changes only when an ADMIN approves the request.
   */
  static async createRechargeByCode(req: AuthenticatedRequest, res: Response) {
    try {
      const createdReq = await ResellerService.createRequest(req.user!.id, req.body)
      return created(res, createdReq, 'Recharge request submitted — waiting for approval')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  // -------------------------------------------------------------------
  // Withdraw (hold / reversal flow)
  // -------------------------------------------------------------------

  static async submitWithdrawal(req: AuthenticatedRequest, res: Response) {
    try {
      const result = await WithdrawService.submit(req.user!.id, req.body)
      return created(res, result, 'Withdrawal submitted — diamonds held until reviewed')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async myWithdrawals(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await WithdrawService.mine(req.user!.id))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  /**
   * LEGACY direct-withdraw endpoint kept for old clients: now routed through
   * the same hold/review RPC flow as the real one (previously it deducted
   * immediately with no review queue).
   */
  static async withdrawDiamonds(req: AuthenticatedRequest, res: Response) {
    try {
      const amount = Number(req.body.amount)
      const payment_method = typeof req.body.payment_method === 'string' ? req.body.payment_method : ''
      const payment_details =
        typeof req.body.payment_details === 'string' ? req.body.payment_details.slice(0, 200) : ''

      if (!isPositiveInt(amount)) return error(res, 400, 'Invalid withdrawal amount')
      if (!payment_method) return error(res, 400, 'Payment method required')

      const method = ['bkash', 'nagad', 'bank_transfer'].includes(payment_method)
        ? payment_method : 'other'
      const result = await WithdrawService.submit(req.user!.id, {
        diamonds_requested: amount,
        payout_method: method,
        payout_details: payment_details ? { note: payment_details } : { source: 'legacy-client' },
      })
      return success(res, result, 'Withdrawal requested')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }
}
