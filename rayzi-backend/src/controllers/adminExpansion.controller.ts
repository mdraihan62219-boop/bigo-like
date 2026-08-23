import { Response } from 'express'
import { ShopService } from '../services/shop.service'
import { ResellerService } from '../services/reseller.service'
import { HostApplicationService } from '../services/hostApplication.service'
import { supabase } from '../config/database'
import { success, created, error } from '../utils/response'
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
