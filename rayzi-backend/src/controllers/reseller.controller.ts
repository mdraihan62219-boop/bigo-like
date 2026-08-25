import { Response } from 'express'
import { ResellerService } from '../services/reseller.service'
import { success, created, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class ResellerController {
  static async createRequest(req: AuthenticatedRequest, res: Response) {
    try {
      return created(res, await ResellerService.createRequest(req.user!.id, req.body), 'Request submitted')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async myRequests(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await ResellerService.myRequests(req.user!.id))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  /** Reseller Dashboard payload — agent row (or null), pending queue, ledger. */
  static async dashboard(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await ResellerService.dashboard(req.user!.id))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  /** Approve from the reseller dashboard. Ownership scoping lives in the RPC. */
  static async approveScoped(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const result = await ResellerService.approveScoped(id, req.user!.id)
      if (!result.ok) return error(res, 403, result.message)
      return success(res, null, 'Request approved')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  /** Reject from the reseller dashboard. Ownership scoping lives in the RPC. */
  static async rejectScoped(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const reason = typeof req.body?.reason === 'string' && req.body.reason.trim()
        ? req.body.reason.trim() : 'Rejected by reseller'
      const result = await ResellerService.rejectScoped(id, req.user!.id, reason)
      if (!result.ok) return error(res, 403, result.message)
      return success(res, null, 'Request rejected')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
