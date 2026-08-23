import { Response } from 'express'
import { FriendService } from '../services/friend.service'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class FriendController {
  static async sendRequest(req: AuthenticatedRequest, res: Response) {
    try {
      const r = await FriendService.sendRequest(req.user!.id, req.params.userId)
      if (!r.ok) return error(res, r.status, r.message)
      return res.status(r.status).json({ success: true, data: r.data, message: r.message })
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async respond(req: AuthenticatedRequest, res: Response) {
    try {
      const accept = req.path.endsWith('/accept')
      const r = await FriendService.respond(req.user!.id, req.params.requestId, accept)
      if (!r.ok) return error(res, r.status, r.message)
      return success(res, r.data, accept ? 'Friend added' : 'Request rejected')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await FriendService.listFriends(req.user!.id))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async requests(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await FriendService.listRequests(req.user!.id))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async count(req: AuthenticatedRequest, res: Response) {
    try {
      const c = await FriendService.count(req.params.userId)
      return success(res, { count: c })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
