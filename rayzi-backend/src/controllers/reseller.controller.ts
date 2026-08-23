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
}
