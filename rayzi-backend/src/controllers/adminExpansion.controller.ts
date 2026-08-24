import { Response } from 'express'
import { ShopService } from '../services/shop.service'
import { ResellerService } from '../services/reseller.service'
import { HostApplicationService } from '../services/hostApplication.service'
import { WithdrawService } from '../services/withdraw.service'
import { supabase } from '../config/database'
import { success, created, error } from '../utils/response'
import { pageParam, limitParam } from '../utils/pagination'
import { AuthenticatedRequest } from '../types'

/** Admin-only endpoints for the v2 expansion (shop / reseller / host apps / PK). */
export class AdminExpansionController {
  static async shopList(_req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await ShopService.adminListItems())
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async shopCreate(req: AuthenticatedRequest, res: Response) {
    try {
      return created(res, await ShopService.adminCreateItem(req.body), 'Item created')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async shopUpdate(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await ShopService.adminUpdateItem(req.params.id, req.body), 'Item updated')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async shopDelete(req: AuthenticatedRequest, res: Response) {
    try {
      await ShopService.adminDeleteItem(req.params.id)
      return success(res, null, 'Item deleted')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async resellerRequests(req: AuthenticatedRequest, res: Response) {
    try {
      const status = typeof req.query.status === 'string' ? req.query.status : undefined
      return success(res, await ResellerService.adminListRequests(status))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async resellerApprove(req: AuthenticatedRequest, res: Response) {
    try {
      const r = await ResellerService.adminApprove(req.params.id, req.user!.id)
      if (!r.ok) return error(res, 400, r.message)
      req.app.get('io')?.to(`user_${req.params.id}`).emit('recharge-status', { requestId: req.params.id, status: 'approved' })
      return success(res, null, 'Recharge approved')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async resellerReject(req: AuthenticatedRequest, res: Response) {
    try {
      const reason = typeof req.body.reason === 'string' ? req.body.reason.slice(0, 500) : undefined
      const r = await ResellerService.adminReject(req.params.id, req.user!.id, reason ?? 'Rejected by admin')
      if (!r.ok) return error(res, 400, r.message)
      req.app.get('io')?.to(`user_${req.params.id}`).emit('recharge-status', { requestId: req.params.id, status: 'rejected' })
      return success(res, null, 'Recharge rejected')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async resellerAgents(req: AuthenticatedRequest, res: Response) {
    try {
      if (req.method === 'POST') {
        return created(res, await ResellerService.adminUpsertAgent(req.body), 'Agent saved')
      }
      return success(res, await ResellerService.adminListAgents())
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  // -----------------------------------------------------------------
  // Wallet Ledger / Adjustments (financial audit view)
  // -----------------------------------------------------------------

  /** Full ledger across all users; filter by user, reason or admin_code. */
  static async walletLedger(req: AuthenticatedRequest, res: Response) {
    try {
      const page = pageParam(req.query.page)
      const limit = Math.min(limitParam(req.query.limit), 100)
      let query = supabase
        .from('wallet_ledger')
        .select(`
          *,
          actor:profiles!wallet_ledger_actor_id_fkey(username, admin_code, display_name)
        `, { count: 'exact' })

      const userId = typeof req.query.user_id === 'string' ? req.query.user_id : ''
      if (userId && /^[0-9a-f-]{36}$/i.test(userId)) query = query.eq('user_id', userId)
      const reason = typeof req.query.reason === 'string' ? req.query.reason : ''
      if (reason) query = query.eq('reason', reason)
      const adminCode = typeof req.query.admin_code === 'string' ? req.query.admin_code.trim() : ''
      if (adminCode) query = query.filter('actor.admin_code', 'eq', adminCode)

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((page - 1) * limit, page * limit - 1)
      return success(res, data ?? [], undefined, { page, limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  /** Manual grant/deduction — always audited via the ledger row inside the RPC. */
  static async adjustBalance(req: AuthenticatedRequest, res: Response) {
    try {
      const userId = typeof req.body?.user_id === 'string' ? req.body.user_id : ''
      const currency = typeof req.body?.currency === 'string' ? req.body.currency : ''
      const amount = Number(req.body?.amount)
      const note = typeof req.body?.note === 'string' ? req.body.note.slice(0, 500) : ''
      if (!/^[0-9a-f-]{36}$/i.test(userId)) return error(res, 400, 'valid user_id required')
      if (!['coins', 'diamonds'].includes(currency)) return error(res, 400, 'currency must be coins|diamonds')
      if (!Number.isInteger(amount) || amount === 0) return error(res, 400, 'non-zero integer amount required')
      if (note.length < 3) return error(res, 400, 'a reason/note is required')

      const { data, error: rpcError } = await supabase.rpc('admin_adjust_balance', {
        p_admin: req.user!.id,
        p_user_id: userId,
        p_currency: currency,
        p_amount: amount,
        p_note: note,
      })
      if (rpcError) return error(res, 400, rpcError.message)
      return created(res, data, 'Balance adjusted and logged in the ledger')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  // -----------------------------------------------------------------
  // Withdraw queue
  // -----------------------------------------------------------------

  static async withdrawQueue(req: AuthenticatedRequest, res: Response) {
    try {
      const status = typeof req.query.status === 'string' ? req.query.status : undefined
      return success(res, await WithdrawService.adminList(status))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async withdrawDecide(req: AuthenticatedRequest, res: Response) {
    try {
      const id = req.params.id
      let result
      if (req.path.endsWith('/approve')) {
        result = await WithdrawService.adminApprove(id, req.user!.id)
      } else if (req.path.endsWith('/paid')) {
        result = await WithdrawService.adminMarkPaid(id, req.user!.id)
      } else {
        const reason = typeof req.body?.reason === 'string' && req.body.reason.trim()
          ? req.body.reason.trim().slice(0, 500) : ''
        if (!reason) return error(res, 400, 'A rejection reason is required')
        result = await WithdrawService.adminReject(id, req.user!.id, reason)
      }
      if (!result.ok) return error(res, 400, result.message)

      // Notify the requester over their socket room.
      const event = req.path.endsWith('/reject') ? 'rejected' : req.path.endsWith('/paid') ? 'paid' : 'approved'
      const { data: wr } = await supabase.from('withdraw_requests').select('user_id').eq('id', id).single()
      if (wr) req.app.get('io')?.to(`user_${wr.user_id}`).emit('withdraw-status', { requestId: id, status: event })
      return success(res, null, `Withdrawal ${event}`)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async hostApplications(req: AuthenticatedRequest, res: Response) {
    try {
      const status = typeof req.query.status === 'string' ? req.query.status : 'pending'
      return success(res, await HostApplicationService.adminList(status))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async hostApplicationDecide(req: AuthenticatedRequest, res: Response) {
    try {
      const approve = req.path.endsWith('/approve')
      const reason = typeof req.body?.reason === 'string' ? req.body.reason.slice(0, 500) : undefined
      const r = await HostApplicationService.adminDecide(req.params.id, req.user!.id, approve, reason)
      if (!r.ok) return error(res, 400, r.message)
      req.app.get('io')?.to(`user_${req.params.id}`).emit('host-application-status', { status: approve ? 'approved' : 'rejected' })
      return success(res, null, approve ? 'Host approved' : 'Host application rejected')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async pkDragonStages(req: AuthenticatedRequest, res: Response) {
    try {
      const stage = Number(req.body.stage)
      const threshold = Number(req.body.score_threshold)
      const label = typeof req.body.label === 'string' ? req.body.label.slice(0, 40) : null
      if (!Number.isInteger(stage) || stage < 0 || stage > 4 || !Number.isInteger(threshold) || !label) {
        return error(res, 400, 'stage(0-4), label and score_threshold required')
      }
      const patch: Record<string, unknown> = { label, score_threshold: threshold }
      if (typeof req.body.animation_url === 'string') patch.animation_url = req.body.animation_url.slice(0, 1000)
      const { data, error: dbError } = await supabase
        .from('pk_dragon_stages').upsert({ stage, ...patch }, { onConflict: 'stage' }).select().single()
      if (dbError) return error(res, 400, dbError.message)
      return success(res, data, 'Dragon stage saved')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
